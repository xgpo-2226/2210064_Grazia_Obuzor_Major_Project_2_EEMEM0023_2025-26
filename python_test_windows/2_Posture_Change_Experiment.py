# tracks HR and breathing rate for 3-phase posture comparison (Sitting, Standing, Re-sitting)
# packet format: AAAA,PPPP,RRRR,QQQQ,CCCC,S\r\n
# adapted from tachogram view display

import time, threading, serial, numpy as np
from scipy.signal import welch
import pyqtgraph as pg
from pyqtgraph.Qt import QtCore, QtWidgets

try:
    import sounddevice as sd
    AUDIO_OK = True
except ImportError:
    AUDIO_OK = False

# Settings
PORT       = 'COM4'
BAUD       = 115200
SAMPLE_HZ  = 250
PHASE_MIN  = 3           # minutes per phase
HR_WIN     = 16
SNR_MIN    = 1.3
BEAT_BUF  = 60            # 1minute buffer of beats

PHASES  = ['SITTING', 'STANDING', 'RE-SITTING']
COLOURS  = [(0,120,200), (0,160,80), (200,80,0)]
TOTAL_S = PHASE_MIN * 60 * len(PHASES) # total experiment time

ser = serial.Serial(PORT, BAUD, timeout=0.1)

# beep waveform for debugging
if AUDIO_OK:
    n = int(44100 * 0.03)  # 30 ms at 44100 Hz
    t = np.linspace(0, 0.03, n, endpoint=False)
    fade = np.ones(n)
    hw = max(1, int(n * 0.3))
    win = 0.5 * (1 - np.cos(np.pi * np.arange(hw) / hw))
    fade[:hw] = win; fade[-hw:] = win[::-1]
    BEEP = (0.4 * np.sin(2 * np.pi * 880 * t) * fade).astype(np.float32)
    
def beep():
    # plays a short tone on each detected heartbeat
    if AUDIO_OK:
        threading.Thread(target=sd.play, args=(BEEP, 44100),
                         kwargs={'blocking': False}, daemon=True).start()

# colours for overlayed HR and br/min metrics
pg.setConfigOption('foreground','k')
COL_HR=(180,0,0)
COL_M1=(180,90,0)
COL_M2=(0,100,170)
COL_M3=(110,0,180)
def pen(c,w=1): return pg.mkPen(c,width=w)

# window with control button + 3 plot rows
app = QtWidgets.QApplication([])
main = QtWidgets.QWidget()
main.setWindowTitle(f"ECG Posturing — {PHASE_MIN} min/phase × {len(PHASES)} postures")
main.resize(1500, 920)
layout = QtWidgets.QVBoxLayout(main)

# next-phase button showing phase and elapsed time
bar = QtWidgets.QHBoxLayout()
phase_lbl = QtWidgets.QLabel(f"Phase: SITTING (1/{len(PHASES)})")
phase_lbl.setStyleSheet("font-size:16px; font-weight:bold; color:rgb(0,120,200);")
bar.addWidget(phase_lbl); bar.addStretch()
elapsed_lbl = QtWidgets.QLabel("Phase: 0:00 / 3:00")
elapsed_lbl.setStyleSheet("font-size:14px; color:#444;")
bar.addWidget(elapsed_lbl); bar.addSpacing(20)
btn = QtWidgets.QPushButton("▶  NEXT PHASE")
btn.setFixedSize(180, 44)
btn.setStyleSheet("font-size:15px; font-weight:bold; background:#0060c0; "
                  "color:white; border-radius:6px;")
bar.addWidget(btn)
layout.addLayout(bar)

gw = pg.GraphicsLayoutWidget(); gw.setBackground('w'); layout.addWidget(gw)

# ecg sinus trace
ecg_plot = gw.addPlot(title="Live ECG"); ecg_plot.setYRange(0,4096)
ecg_crv = ecg_plot.plot(pen=pen((0,130,0))); ecg_buf = np.zeros(1250)

# HR over time
gw.nextRow()
hr_plot = gw.addPlot(title="Heart Rate over Posture Phases")
hr_plot.setLabel('left','BPM'); hr_plot.setLabel('bottom','s')
hr_plot.setXRange(0,TOTAL_S); hr_plot.setYRange(40,160)
hr_crv = hr_plot.plot(pen=pen(COL_HR,2))
hr_lbl = pg.TextItem("",color=COL_HR,anchor=(1,0))
hr_plot.addItem(hr_lbl); hr_lbl.setPos(TOTAL_S-2,155)

# breathing rates over time
gw.nextRow()
br_plot = gw.addPlot(title="Breathing Rate (M1 Amp | M2 RSA | M3 Area)")
br_plot.setLabel('left','br/min'); br_plot.setLabel('bottom','s')
br_plot.setXRange(0,TOTAL_S); br_plot.setYRange(5,35)
br1_crv = br_plot.plot(pen=pen(COL_M1,2))
br2_crv = br_plot.plot(pen=pen(COL_M2,2))
br3_crv = br_plot.plot(pen=pen(COL_M3,2))
br1_lbl = pg.TextItem("",color=COL_M1,anchor=(1,0))
br2_lbl = pg.TextItem("",color=COL_M2,anchor=(1,0))
br3_lbl = pg.TextItem("",color=COL_M3,anchor=(1,0))
br_plot.addItem(br1_lbl); br1_lbl.setPos(TOTAL_S-2,33)
br_plot.addItem(br2_lbl); br2_lbl.setPos(TOTAL_S-2,29)
br_plot.addItem(br3_lbl); br3_lbl.setPos(TOTAL_S-2,25)
for i,(c,t) in enumerate([(COL_M1,'M1 Amp'),(COL_M2,'M2 RSA'),(COL_M3,'M3 Area')]):
    l=pg.TextItem(f"■ {t}",color=c,anchor=(0,0)); br_plot.addItem(l); l.setPos(2,33-i*3)

# phase shading
def shade(plot, idx, s, e):
    r,g,b=COLOURS[idx]
    plot.addItem(pg.LinearRegionItem([s,e],brush=pg.mkBrush(r,g,b,25),movable=False))
def label(plot, idx, s, y):
    r,g,b=COLOURS[idx]
    t=pg.TextItem(PHASES[idx],color=(r,g,b),anchor=(0,1)); plot.addItem(t); t.setPos(s+2,y)

# draw initial phase shading
for p in [hr_plot, br_plot]:
    shade(p, 0, 0, PHASE_MIN*60)
    label(p, 0, 0, 155 if p is hr_plot else 33)
main.show()

# phase and elapsed times
amp_buf=np.zeros(BEAT_BUF)
rr_buf=np.zeros(BEAT_BUF)
area_buf=np.zeros(BEAT_BUF)
hr_rbuf=np.zeros(HR_WIN)
ts,ts_hr,ts_b1,ts_b2,ts_b3 = [],[],[],[],[]
hr_count=beat_count=psd_ctr=sample_ctr=0
cached=[np.nan,np.nan,np.nan]
t0=time.time()
phase_t0=time.time()
cur_phase=0

def advance():
    # to the next posture phase 
    # update phase start time
    global cur_phase, phase_t0
    if cur_phase >= len(PHASES)-1: return
    cur_phase += 1
    phase_t0 = time.time()
    now = time.time()-t0
    end = now + PHASE_MIN*60
    for p in [hr_plot, br_plot]:
        shade(p, cur_phase, now, end)
        p.addItem(pg.InfiniteLine(pos=now,angle=90,
            pen=pg.mkPen((80,80,80),width=1,style=QtCore.Qt.DashLine)))
        label(p, cur_phase, now, 155 if p is hr_plot else 33)
    r,g,b = COLOURS[cur_phase]
    phase_lbl.setText(f"Phase: {PHASES[cur_phase]} ({cur_phase+1}/{len(PHASES)})")
    phase_lbl.setStyleSheet(f"font-size:16px;font-weight:bold;color:rgb({r},{g},{b});")
    if cur_phase == len(PHASES)-1:
        btn.setEnabled(False)
        btn.setText("Recording…")

btn.clicked.connect(advance)

def psd_br(seq, filled):
    if filled<16: return np.nan
    d=seq[-filled:].astype(float)
    d-=np.linspace(d[0],d[-1],len(d))
    if np.var(d)<0.5: return np.nan
    fs=1.0/max(np.mean(rr_buf[-filled:])/1000.0,0.3)
    f,p=welch(d,fs=fs,nperseg=min(filled,32))
    m=(f>=0.15)&(f<=0.4)
    if not m.any(): return np.nan
    b=p[m]
    if np.mean(b)<=0 or np.max(b)<SNR_MIN*np.mean(b): return np.nan
    return f[m][np.argmax(b)]*60.0

def process(line):
    global ecg_buf,amp_buf,rr_buf,area_buf,hr_rbuf
    global hr_count,beat_count,psd_ctr,sample_ctr,cached
    try:
        p=line.split(',')
        adc=int(p[0])
        peak=int(p[1])
        rr=int(p[2])
        area=int(p[3])
    except (ValueError,IndexError): return

    ecg_buf=np.roll(ecg_buf,-1)
    ecg_buf[-1]=np.clip(adc,0,4095)
    sample_ctr+=1
    if sample_ctr%10==0: ecg_crv.setData(ecg_buf)

    if rr<=0: return # if no new beat, HR and br/min can't be found yet

    rr_ms=int(rr*1000/SAMPLE_HZ)
    if not (300<=rr_ms<=1800): return
    beep() # heartbeat found
    hr_rbuf=np.roll(hr_rbuf,-1)
    hr_rbuf[-1]=rr_ms
    hr_count=min(hr_count+1,HR_WIN)

    bpm=float(60000/np.median(hr_rbuf[-hr_count:])) if hr_count>0 else 0
    beat_count=min(beat_count+1,60)
    psd_ctr+=1

    # update tachogram buffers for PSD BR estimates
    amp_buf=np.roll(amp_buf,-1)
    amp_buf[-1]=peak

    rr_buf=np.roll(rr_buf,-1)
    rr_buf[-1]=rr_ms

    area_buf=np.roll(area_buf,-1)
    area_buf[-1]=area

    # re-calculate resp rate every 5 beats
    if psd_ctr>=5:
        psd_ctr=0
        r1=psd_br(amp_buf,beat_count)
        r2=psd_br(rr_buf,beat_count)
        r3=psd_br(area_buf,beat_count)
        if not np.isnan(r1):cached[0]=r1
        if not np.isnan(r2):cached[1]=r2
        if not np.isnan(r3):cached[2]=r3
    elapsed=time.time()-t0
    ts.append(elapsed)
    ts_hr.append(bpm)

    ts_b1.append(cached[0])
    ts_b2.append(cached[1])
    ts_b3.append(cached[2])

    ta=np.array(ts)

    hr_crv.setData(ta,np.array(ts_hr))
    br1_crv.setData(ta,np.array(ts_b1,dtype=float))
    br2_crv.setData(ta,np.array(ts_b2,dtype=float))
    br3_crv.setData(ta,np.array(ts_b3,dtype=float))
    hr_lbl.setHtml(f'<span style="font-size:16pt;font-weight:bold;color:#b40000">HR: {int(bpm)} BPM</span>')
    def fmt(v,c):
        if np.isnan(v): return f'<span style="font-size:12pt;font-weight:bold;color:{c}">--</span>'
        return f'<span style="font-size:12pt;font-weight:bold;color:{c}">{v:.1f} br/min</span>'
    br1_lbl.setHtml("M1: "+fmt(cached[0],'#b45a00'))
    br2_lbl.setHtml("M2: "+fmt(cached[1],'#0064aa'))
    br3_lbl.setHtml("M3: "+fmt(cached[2],'#6e00b4'))

def tick():
    pe=time.time()-phase_t0
    m,s=int(pe)//60, int(pe)%60
    elapsed_lbl.setText(f"Phase: {m}:{s:02d} / {PHASE_MIN}:00")
    for _ in range(40):
        if ser.in_waiting==0: break
        line=ser.readline().decode('ascii',errors='ignore').strip()
        if line: process(line)

timer=QtCore.QTimer()
timer.timeout.connect(tick)
timer.start(20)

if __name__=='__main__': 
    app.exec_()
    ser.close()