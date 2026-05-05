# plots serial data from FPGA: sinus trace, tachograms, PSD for EDR rates, apnoea count
# packet format: AAAA,PPPP,RRRR,QQQQ,CCCC,S\r\n

import time, threading, serial, numpy as np
from scipy.signal import welch
import pyqtgraph as pg
from pyqtgraph.Qt import QtCore, QtWidgets

# beeps on each heartbeat
try:
    import sounddevice as sd; AUDIO_OK = True
except ImportError:
    AUDIO_OK = False

# key settings
PORT      = 'COM4'       # serial port used for testing
BAUD      = 115200       # to match FPGA UART baud rate
SAMPLE_HZ = 250          # FPGA sampling rate
HR_WIN    = 16            # number of beats used for median heart rate
SNR_MIN   = 2.0           # minimum SNR for valid breathing rate
BEAT_BUF  = 60            # 1minute buffer of beats

# sesrial port
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
    # plays a short tone on each detected heartbeat and stops when window closes
    if AUDIO_OK:
        threading.Thread(target=sd.play, args=(BEEP, 44100),
                         kwargs={'blocking': False}, daemon=True).start()

# apnoea timeline colours
pg.setConfigOption('foreground', 'k')
GREEN  = (0, 130, 0)
ORANGE = (180, 90, 0)
BLUE   = (0, 100, 170)
PURPLE = (110, 0, 180)
STATE_COLOURS = {0: (0,150,0), 1: (180,120,0), 2: (200,0,0)}
STATE_NAMES   = {0: 'NORMAL',  1: 'HYPOPNOEA', 2: 'APNOEA'}

# plot window
app = QtWidgets.QApplication([])
win = pg.GraphicsLayoutWidget(show=True, title="FPGA ECG Monitor")
win.resize(1500, 1050); win.setBackground('w')

# live ECG waveform
ecg_plot = win.addPlot(title="Live ECG (FIR-filtered)", colspan=3)
ecg_plot.setYRange(0, 4096)
ecg_plot.enableAutoRange('y', True)
ecg_curve = ecg_plot.plot(pen=pg.mkPen(GREEN))
info_lbl = pg.TextItem("HR: --", color='k', anchor=(0, 0))
ecg_plot.addItem(info_lbl); info_lbl.setPos(0, 3900)

# three tachograms (one dot per heartbeat)
win.nextRow()
amp_plot = win.addPlot(title="M1: R-peak amplitude")
amp_crv  = amp_plot.plot(pen=pg.mkPen(ORANGE), symbol='o', symbolSize=4,
                        symbolBrush=pg.mkBrush(ORANGE))
rr_plot  = win.addPlot(title="M2: RR interval (RSA)")
rr_plot.setYRange(400, 1400)
rr_crv   = rr_plot.plot(pen=pg.mkPen(BLUE), symbol='o', symbolSize=4,
                        symbolBrush=pg.mkBrush(BLUE))
area_plot = win.addPlot(title="M3: QRS area")
area_crv  = area_plot.plot(pen=pg.mkPen(PURPLE), symbol='o', symbolSize=4,
                        symbolBrush=pg.mkBrush(PURPLE))

# three PSD plots (respiratory frequency spectra)
win.nextRow()
def make_psd(title, col):
    p = win.addPlot(title=title)
    p.setXRange(0.05, 0.5) # for context w.r.t noise artifacts
    c = p.plot(pen=pg.mkPen(col))
    line = pg.InfiniteLine(angle=90, pen=pg.mkPen((160,0,0), width=2))
    p.addItem(line)
    lbl = pg.TextItem("-- br/min", color=(140,0,0), anchor=(0,1))
    p.addItem(lbl)
    r,g,b = col
    p.addItem(pg.LinearRegionItem([0.15, 0.4], brush=pg.mkBrush(r,g,b,40), movable=False))
    return c, line, lbl

# main frequencies from the decomposition of the tachogram waves
psd1_crv, psd1_line, psd1_lbl = make_psd("PSD — amplitude", ORANGE)
psd2_crv, psd2_line, psd2_lbl = make_psd("PSD — RR / RSA", BLUE)
psd3_crv, psd3_line, psd3_lbl = make_psd("PSD — QRS area", PURPLE)

# apnoea timeline
win.nextRow()
ap_plot = win.addPlot(title="Apnoea state (FPGA)", colspan=3)
ap_plot.setYRange(-0.3, 2.6)
ap_plot.getAxis('left').setTicks([[(0,'NORMAL'),(1,'HYPO'),(2,'APNOEA')]])
ap_crv = ap_plot.plot(pen=pg.mkPen('k', width=2))
ap_lbl = pg.TextItem("● NORMAL", color=(0,150,0), anchor=(1,0))
ap_plot.addItem(ap_lbl); ap_lbl.setPos(750, 2.5)
evt_lbl = pg.TextItem("Events: 0", color='k', anchor=(0,0))
ap_plot.addItem(evt_lbl); evt_lbl.setPos(0, 2.5)

# plotting data buffers
ecg_buf  = np.zeros(2500)       # 10 seconds of the sinus trace (at 250 Hz)
amp_buf  = np.zeros(BEAT_BUF)   # last 60 peak amplitudes
rr_buf   = np.zeros(BEAT_BUF)   # RR intervals (ms)
area_buf = np.zeros(BEAT_BUF)   # QRS areas
ap_hist  = np.zeros(750)        # apnoea state 3 sec window
hr_buf   = np.zeros(HR_WIN)     # last 16 RR values for median HR

beat_count = hr_count = psd_ctr = sample_ctr = 0
last_info = time.time()
cached_br = ['--', '--', '--']  # most recent breathing rates (start at null)


def welch_br(seq, filled, lbl, line, crv):
    if filled < 16: return '--' # minimum ammount of beats needed at start up firstly
    data = seq[-filled:].astype(float)
    data -= np.linspace(data[0], data[-1], len(data))  # detrend
    if np.var(data) < 0.5: lbl.setText("-- br/min"); return '--'

    # sampling rate in beats/sec (inverse of mean RR in seconds)
    fs = 1.0 / max(np.mean(rr_buf[-filled:]) / 1000.0, 0.3)
    freqs, psd = welch(data, fs=fs, nperseg=min(filled, 32)) # estimate PSD from decomposition
    crv.setData(freqs, psd)

    # look only for a peak in the respiratory band (9–24 br/min e.g. 0.15–0.4 Hz)
    mask = (freqs >= 0.15) & (freqs <= 0.4)
    if not mask.any(): return '--'
    band = psd[mask]
    if np.mean(band) <= 0 or np.max(band) < SNR_MIN * np.mean(band):
        lbl.setText("-- br/min"); return '--'

    pk_freq = freqs[mask][np.argmax(band)]
    br = pk_freq * 60.0
    line.setValue(pk_freq)
    lbl.setText(f"{br:.1f} br/min"); lbl.setPos(pk_freq, np.max(band)*0.9)
    return f"{br:.1f}" # returns the peak frequency in br/min, or '--' if unreliable


def process(line):
    # update all plots after each packet processed
    global ecg_buf, amp_buf, rr_buf, area_buf, ap_hist, hr_buf
    global beat_count, hr_count, psd_ctr, sample_ctr, last_info, cached_br

    # process the 6 comma-separated fields in the serial packet
    try:
        p = line.split(',')
        adc  = int(p[0])   # filtered ECG value
        peak = int(p[1])   # R-peak amplitude
        rr   = int(p[2])   # RR interval (samples, 0 if no beat) 
                           # useful trigger for tachogram update
        area = int(p[3])   # QRS area
        # cached rates and apnoea metrics here are used for the plot display
        evts = int(p[4])   # apnoea event count
        state= int(p[5])   # apnoea state (0/1/2)
    except (ValueError, IndexError):
        return

    # update ECG waveform (shift buffer left, add new sample)
    ecg_buf = np.roll(ecg_buf, -1); ecg_buf[-1] = np.clip(adc, 0, 4095)
    sample_ctr += 1
    if sample_ctr % 5 == 0: ecg_curve.setData(ecg_buf)

    # update apnoea timeline
    ap_hist = np.roll(ap_hist, -1); ap_hist[-1] = state
    if sample_ctr % 5 == 0: ap_crv.setData(ap_hist)
    ap_lbl.setText(f"● {STATE_NAMES[state]}"); ap_lbl.setColor(STATE_COLOURS[state])
    evt_lbl.setText(f"Events: {evts}")

    # skip the tachogram update if no detected beat
    if rr <= 0: return
    rr_ms = int(rr * 1000 / SAMPLE_HZ)
    if not (300 <= rr_ms <= 1800): return  # safeguard for noise/unrealistic breath rate
    beep()

    # compute heart rate from median of last 16 RR intervals
    hr_buf = np.roll(hr_buf, -1); hr_buf[-1] = rr_ms
    hr_count = min(hr_count + 1, HR_WIN)
    med = np.median(hr_buf[-hr_count:])
    bpm = int(60000 / med) if med > 0 else 0

    # add this beat to the tachogram buffers
    beat_count = min(beat_count + 1, BEAT_BUF); psd_ctr += 1
    amp_buf  = np.roll(amp_buf, -1);  amp_buf[-1]  = peak
    rr_buf   = np.roll(rr_buf, -1);   rr_buf[-1]   = rr_ms
    area_buf = np.roll(area_buf, -1); area_buf[-1] = area
    amp_crv.setData(amp_buf[-beat_count:])
    rr_crv.setData(rr_buf[-beat_count:])
    area_crv.setData(area_buf[-beat_count:])

    # every 5 beats, recalculate breathing rate from each tachogram
    if psd_ctr >= 5:
        psd_ctr = 0
        r1 = welch_br(amp_buf,  beat_count, psd1_lbl, psd1_line, psd1_crv)
        r2 = welch_br(rr_buf,   beat_count, psd2_lbl, psd2_line, psd2_crv)
        r3 = welch_br(area_buf, beat_count, psd3_lbl, psd3_line, psd3_crv)
        if r1 != '--': cached_br[0] = r1
        if r2 != '--': cached_br[1] = r2
        if r3 != '--': cached_br[2] = r3

    # update the info bar every 5 seconds
    if time.time() - last_info >= 5:
        last_info = time.time()
        info_lbl.setText(
            f"HR: {bpm} BPM | M1: {cached_br[0]} | "
            f"M2: {cached_br[1]} | M3: {cached_br[2]} | "
            f"State: {STATE_NAMES[state]} | Events: {evts}")


def tick():
    # reads all available serial data every 20ms
    for _ in range(30):
        if ser.in_waiting == 0: break
        line = ser.readline().decode('ascii', errors='ignore').strip()
        if line: process(line)

timer = QtCore.QTimer()
timer.timeout.connect(tick)
timer.start(20)

if __name__ == '__main__':
    QtWidgets.QApplication.instance().exec_()
    ser.close()