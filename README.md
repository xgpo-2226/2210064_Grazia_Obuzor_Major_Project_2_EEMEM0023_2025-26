# 2210064_Grazia_Obuzor_Major_Project_2_EEMEM0023_2025-26
Supplementary Code and Appendix Material for Major Project 2 

# FPGA-Enabled Real-Time Multiparameter Acquisition from Commercial 3-lead ECG Platform

Implemented on a Digilent Cmod A7 (Xilinx Artix-7 XC7A35T-CPG236-1) FPGA.  Captures a 3-lead ECG signal via the on-chip XADC pins, applies FIR bandpass filtering and Pan-Tompkins-inspired R-peak detection in hardware, and streams diagnostic packets over UART at 115 200 baud to Python-based rendering scripts for live visualisation of heart rate,
ECG-derived respiration (EDR), and breath hold (`apnoea`) detection.

## Repository structure
```
├── src/                        # VHDL source files
│   ├── top_ecg.vhd             # Top-level wrapper (structural)
│   ├── fir_bandpass.vhd        # 12-tap symmetric FIR bandpass (Q9)
│   ├── peak_detector.vhd       # R-peak,EDR envelopes, and breath hold detection
│   ├── tx_packetiser.vhd       # 28-byte UART packet builder FSM
│   └── uart_tx.vhd             # UART transmitter (115200)
├── constrs/
│   └── CmodA7_ECG.xdc             # Pin assignments and clock constraint
├── ip/
│   └── xadc_wiz_0.xci          # XADC Wizard IP configuration (using VAUX4 channels)
├── python_test_windows/
│   ├── 1_Tachogram_View.py      # Main 4-row dashboard (sinus reading, tachograms + WPSD + `apnoea` flagger)
│   ├── 2_Posture_Change_Experiment.py   # 3-phase posture comparison
│   └── 3_HRR_Experiment.py  # 5-min HR/BR recovery recorder
<!-- ├── docs/
│   └── ...                     # Project report, datasheets, references -->
├── ecg_fpga_final_implementation.tcl          # Vivado project recreation script
└── README.md                   # This file
```

<!-- ### Analogue input protection

The XADC accepts 0–3.3 V differential input then scales it down to 0-1V
with the board's built-in pull-down network scales the signal into range.
The AD8232 output typically swings 0–3.3 V.  
(Testing showed that removing the external divider and relying on the
board pull-down alone produced cleaner signals with larger QRS amplitude
(~1300 ADC counts peak-to-baseline vs ~500 with divider), enabling a
higher peak detection threshold.)

-->

### Python rendering

For Serial comms, array and advanced math operations, real-time plotting, and heartbeat feedback audio, install all Python dependencies:

```bash
pip install pyserial numpy scipy pyqtgraph PyQt5 sounddevice
```

## Building the Vivado project

### Option A — From TCL script

1. git clone this repo to a local drive
2. Open Vivado and from the start up window (as in the image below); then, 
   in the Tcl Console, `cd /path/to/this/repo`
3. Then run: `source ecg_fpga_final_implementation.tcl`
4. The project opens with all sources, constraints, and IP configured
5. Either **Generate Bitstream** or Program Device in Hardware Manager with pre-built **.bit** file in this repo directly

### Option B — Manual setup

1. Create a new Vivado project targeting `xc7a35tcpg236-1`
2. Add all `.vhd` files from `src/` as Design Sources
3. Add `constraints/CmodA7_ECG.xdc` as a Constraints file
4. Add `ip/xadc_wiz_0.xci`
5. Set `top_ecg` as the top module
6. Synthesise, implement, and generate bitstream


## Running the Python renderers

1. Programme the FPGA and confirm COM port in computers **Design Manager** or equivalent
<!-- 2. Close PuTTY (only one application can hold the COM port) -->
2. Edit the `PORT` variable at the top of the Python script to match <!-- (e.g. `COM4` on Windows, `/dev/ttyUSB0` on Linux) -->
4. Run: **1_Tachogram_View.py** etc.




<br>


<!--
## Key design parameters

All tuneable constants are exposed as generics on the `peak_detector`
entity and set at instantiation in `top_ecg.vhd`:

| Parameter         | Default | Unit    | Purpose                                |
|-------------------|---------|---------|----------------------------------------|
| `PEAK_THRESHOLD`  | 700     | counts  | FIR value for R-peak detection         |
| `REFRACTORY`      | 90      | samples | Post-beat blanking (360 ms)            |
| `MIN_SLOPE`       | 50      | counts  | Minimum rise rate for valid peak       |
| `ENV_AMP_THRESH`  | 50      | counts  | Amplitude envelope breath threshold    |
| `ENV_RR_THRESH`   | 7       | samples | RR envelope breath threshold           |
| `ENV_AREA_THRESH` | 13      | counts  | QRS area envelope breath threshold     |
| `HYPO_LIMIT`      | 750     | samples | No-breath duration for hypopnoea (3 s) |
| `APNOEA_LIMIT`    | 1250    | samples | No-breath duration for apnoea (5 s)    |

-->

<!--
## Known limitations

- **Posture sensitivity:** Supine posture amplifies T-waves relative
  to R-peaks, causing occasional double-detection.  Mitigated via a
  Python-side physiological plausibility filter and semi-recumbent
  positioning.
- **Shallow breathing:** Very shallow respiration produces insufficient
  EDR modulation for reliable apnoea discrimination.  Subjects should
  breathe with moderate depth during baseline acquisition.
- **Motion artefacts:** Arm/torso movement produces transient signal
  spikes that can reset the apnoea breath counter.  The subject must
  remain still during apnoea simulation.
- **Fixed peak threshold:** Unlike the original Pan-Tompkins adaptive
  threshold, this implementation uses a static threshold requiring
  manual tuning per electrode setup.
  -->


<!-- <img src="/../img/tcl_console_in_vivado.png" alt="Screenshot of the TCL console line withing Start Page of VIVADO application" style="width:200px;"> -->

![Screenshot of the TCL console line withing Start Page of VIVADO application](img/tcl_console_in_vivado.png)
