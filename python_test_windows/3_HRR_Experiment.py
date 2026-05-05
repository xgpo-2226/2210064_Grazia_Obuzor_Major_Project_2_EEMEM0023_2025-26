# shows HR and 3 EDR breathing rates over time after exercise
# packet format: AAAA,PPPP,RRRR,QQQQ,CCCC,S\r\n

import time, threading, serial, numpy as np
from scipy.signal import welch
import pyqtgraph as pg
from pyqtgraph.Qt import QtCore, QtWidgets

try:
    import sounddevice as sd; AUDIO_OK = True
except ImportError:
    AUDIO_OK = False

# Settings
PORT       = 'COM4'
BAUD       = 115200
SAMPLE_HZ  = 250
RECORD_MIN = 5 # total experiment time
HR_WIN     = 16
SNR_MIN    = 1.3
RECORD_SEC = RECORD_MIN * 60

ser = serial.Serial(PORT, BAUD, timeout=0.1)

# Beep
if AUDIO_OK:
    n = int(44100 * 0.03)
    t = np.linspace(0, 0.03, n, endpoint=False)
    fade = np.ones(n); hw = max(1, int(n*0.3))
    w = 0.5*(1-np.cos(np.pi*np.arange(hw)/hw))
    fade[:hw]=w; fade[-hw:]=w[::-1]
    BEEP = (0.35*np.sin(2*np.pi*880*t)*fade).astype(np.float32)

def beep():
    if AUDIO_OK:
        threading.Thread(target=sd.play, args=(BEEP,44100),
                         kwargs={'blocking':False}, daemon=True).start()

# colours
pg.setConfigOption('foreground','k')
COL_HR=(180,0,0); COL_M1=(180,90,0); COL_M2=(0,100,170); COL_M3=(110,0,180)
def pen(c, w=1): return pg.mkPen(c, width=w)

# window layout: ECG sinus trace, HR plot, BR plot
app = QtWidgets.QApplication([])
win = pg.GraphicsLayoutWidget(show=True, title="ECG Recovery Mapping")
win.resize(1400, 900); win.setBackground('w')

ecg_plot = win.addPlot(title="Live ECG"); ecg_plot.setYRange(0,4096)
ecg_crv = ecg_plot.plot(pen=pen((0,130,0)))
ecg_buf = np.zeros(1250)

win.nextRow()
hr_plot = win.addPlot(title="Heart Rate Recovery")
hr_plot.setLabel('left','BPM'); hr_plot.setLabel('bottom','Time (s)')
hr_plot.setXRange(0, RECORD_SEC); hr_plot.setYRange(40, 200)
hr_crv = hr_plot.plot(pen=pen(COL_HR, 2))
hr_plot.addItem(pg.InfiniteLine(pos=100, angle=0,
    pen=pg.mkPen((150,150,150), width=1, style=QtCore.Qt.DashLine)))
# live HR and elapsed time labels
hr_lbl = pg.TextItem("", color=COL_HR, anchor=(1,0))
hr_plot.addItem(hr_lbl); hr_lbl.setPos(RECORD_SEC-2, 195)
time_lbl = pg.TextItem(f"00:00 / {RECORD_MIN:02d}:00", color=(80,80,80), anchor=(1,1))
hr_plot.addItem(time_lbl); time_lbl.setPos(RECORD_SEC-2, 46)

win.nextRow()
br_plot = win.addPlot(title="Breathing Rate Recovery (M1 Amp | M2 RSA | M3 Area)")
br_plot.setLabel('left','br/min'); br_plot.setLabel('bottom','Time (s)')
br_plot.setXRange(0, RECORD_SEC); br_plot.setYRange(5, 40)
br1_crv = br_plot.plot(pen=pen(COL_M1, 2))
br2_crv = br_plot.plot(pen=pen(COL_M2, 2))
br3_crv = br_plot.plot(pen=pen(COL_M3, 2))
# Live BR overlays
br1_lbl = pg.TextItem("", color=COL_M1, anchor=(1,0))
br2_lbl = pg.TextItem("", color=COL_M2, anchor=(1,0))
br3_lbl = pg.TextItem("", color=COL_M3, anchor=(1,0))
br_plot.addItem(br1_lbl); br1_lbl.setPos(RECORD_SEC-2, 38)
br_plot.addItem(br2_lbl); br2_lbl.setPos(RECORD_SEC-2, 33)
br_plot.addItem(br3_lbl); br3_lbl.setPos(RECORD_SEC-2, 28)
# legend for EDR plot
for i,(c,t) in enumerate([(COL_M1,'M1 Amp'),(COL_M2,'M2 RSA'),(COL_M3,'M3 Area')]):
    l = pg.TextItem(f"■ {t}", color=c, anchor=(0,0))
    br_plot.addItem(l); l.setPos(2, 38-i*3.5)

# plot buffers
amp_buf = np.zeros(60); rr_buf = np.zeros(60); area_buf = np.zeros(60)
hr_rbuf = np.zeros(HR_WIN)
ts, ts_hr, ts_br1, ts_br2, ts_br3 = [], [], [], [], []
hr_count = beat_count = psd_ctr = sample_ctr = 0
cached = [np.nan, np.nan, np.nan]
t0 = time.time()


def psd_br(seq, filled):
    # welch psd breathing rate estimate from filled buffer
    if filled < 16: return np.nan
    d = seq[-filled:].astype(float)
    d -= np.linspace(d[0], d[-1], len(d))
    if np.var(d) < 0.5: return np.nan
    fs = 1.0 / max(np.mean(rr_buf[-filled:])/1000.0, 0.3)
    f, p = welch(d, fs=fs, nperseg=min(filled,32))
    m = (f >= 0.15) & (f <= 0.4)
    if not m.any(): return np.nan
    b = p[m]
    if np.mean(b)<=0 or np.max(b) < SNR_MIN*np.mean(b): return np.nan
    return f[m][np.argmax(b)] * 60.0 # returns br/min or NaN


def process(line):
    global ecg_buf, amp_buf, rr_buf, area_buf, hr_rbuf
    global hr_count, beat_count, psd_ctr, sample_ctr, cached
    try:
        p = line.split(',')
        adc=int(p[0]); peak=int(p[1]); rr=int(p[2]); area=int(p[3])
    except (ValueError, IndexError):
        return

    ecg_buf = np.roll(ecg_buf,-1); ecg_buf[-1] = np.clip(adc,0,4095)
    sample_ctr += 1
    if sample_ctr % 10 == 0: ecg_crv.setData(ecg_buf)

    if rr <= 0: return
    rr_ms = int(rr*1000/SAMPLE_HZ)
    if not (300 <= rr_ms <= 1800): return
    beep()

    # heart rate (median of last 16 beats)
    hr_rbuf = np.roll(hr_rbuf,-1); hr_rbuf[-1] = rr_ms
    hr_count = min(hr_count+1, HR_WIN)
    bpm = float(60000 / np.median(hr_rbuf[-hr_count:])) if hr_count > 0 else 0

    # tachogram for PSD updates
    beat_count = min(beat_count+1, 60); psd_ctr += 1
    amp_buf = np.roll(amp_buf,-1); amp_buf[-1] = peak
    rr_buf  = np.roll(rr_buf,-1);  rr_buf[-1] = rr_ms
    area_buf= np.roll(area_buf,-1);area_buf[-1] = area

    # PSD breathing rate (every 5 beats as in the tachogram view plot)
    if psd_ctr >= 5:
        psd_ctr = 0
        r1=psd_br(amp_buf,beat_count)
        r2=psd_br(rr_buf,beat_count)
        r3=psd_br(area_buf,beat_count)
        if not np.isnan(r1): cached[0]=r1
        if not np.isnan(r2): cached[1]=r2
        if not np.isnan(r3): cached[2]=r3

    # update window timer
    elapsed = time.time() - t0
    if elapsed <= RECORD_SEC:
        ts.append(elapsed)
        ts_hr.append(bpm)
        ts_br1.append(cached[0])
        ts_br2.append(cached[1])
        ts_br3.append(cached[2])

    # update plots, stop drawring after 5min (though metrics countinue to update)
    ta = np.array(ts)
    hr_crv.setData(ta, np.array(ts_hr))
    br1_crv.setData(ta, np.array(ts_br1,dtype=float))
    br2_crv.setData(ta, np.array(ts_br2,dtype=float))
    br3_crv.setData(ta, np.array(ts_br3,dtype=float))
    hr_lbl.setHtml(f'<span style="font-size:18pt;font-weight:bold;color:#b40000">HR: {int(bpm)} BPM</span>')
    def fmt(v,c):
        if np.isnan(v): return f'<span style="font-size:13pt;font-weight:bold;color:{c}">--</span>'
        return f'<span style="font-size:13pt;font-weight:bold;color:{c}">{v:.1f} br/min</span>'
    br1_lbl.setHtml("M1: "+fmt(cached[0],'#b45a00'))
    br2_lbl.setHtml("M2: "+fmt(cached[1],'#0064aa'))
    br3_lbl.setHtml("M3: "+fmt(cached[2],'#6e00b4'))


def tick():
    m,s = int(time.time()-t0)//60, int(time.time()-t0)%60
    time_lbl.setText(f"{m:02d}:{s:02d} / {RECORD_MIN:02d}:00")
    for _ in range(40):
        if ser.in_waiting == 0: break
        line = ser.readline().decode('ascii',errors='ignore').strip()
        if line: process(line)

timer = QtCore.QTimer(); timer.timeout.connect(tick); timer.start(20)
if __name__ == '__main__':
    QtWidgets.QApplication.instance().exec_() 
    ser.close()