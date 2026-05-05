# design filter with remez and Q9 quantisation (scale by 512) for integer format suitable in vhdl
# print/plot filter coefficients and plot freq response to verify passband

import numpy as np
from scipy.signal import remez, freqz
import matplotlib.pyplot as plt

# filter params
FS       = 250        # ADC sample rate (Hz)
N_TAPS   = 12         # number of filter coefficients (must be even for symmetric, 
                      # lower is ineffective; higher uses more registers)

F_STOP1  = 0.3        # lower stopband edge  (Hz), blocks DC and motion artefact
F_PASS1  = 1        # lower passband edge  (Hz)
F_PASS2  = 40       # upper passband edge  (Hz), above QRS content
F_STOP2  = 45       # upper stopband edge  (Hz), gradual transition to stopband fromupper basband limit
Q_SCALE  = 512        # Q9 scaling factor (2^9 = 512)


# filter design with remez (parks-mclellan type)
# The algorithm iterates to find the coefficient set that equalises the
# maximum error across all band edges for fixed number of taps

nyq   = FS / 2.0 # normalised to nyquist (half of all samples)
bands = [0, F_STOP1, F_PASS1, F_PASS2, F_STOP2, nyq]
gains = [0, 1, 0] # desired gain in stopband and gain band (BPF)

h_float = remez(N_TAPS, bands, gains, fs=FS) # parks-mclellan fir design
                                             # finds optimal equiripple for passband constraints
print("Float coefficients (full filter):")
print(np.round(h_float, 6))


# Q9 floating point scaling
# symmetric filter i.e. h[k] = h[N-1-k].

h_int  = np.round(h_float * Q_SCALE).astype(int)
h_half = h_int[:N_TAPS // 2]     # [h[0], h[1], ..., h[5]]

print(f"\nInteger Q9 coefficients (full, {Q_SCALE}x):")
print(h_int.tolist())
print(f"\nHalf-coefficients for VHDL constant (h[0]..h[{N_TAPS//2 - 1}]):")
print(h_half.tolist())
print(f"\nDC gain check: sum of all integer coefficients = {sum(h_int)}")
print("(Sum is approx. 0 for a bandpass filter; removes DC offset from ADC.)") # when divided by 512

print("\nVHDL constants to use:")
vhdl_vals = ", ".join(str(v) for v in h_half)
print(f"    constant FIR_COEFF : coeff_t := ({vhdl_vals});")


# compare raw floating point to recovered Q9 scaled frequency response (and symmetry of taps):
w_f, H_f = freqz(h_float, worN=4096, fs=FS)
w_i, H_i = freqz(h_int / Q_SCALE, worN=4096, fs=FS)  # normalise back

fig, axes = plt.subplots(2, 1, figsize=(10, 8))
fig.suptitle(f"FIR Bandpass Filter: {N_TAPS}-tap Parks-McClellan at Fs={FS} Hz",
             fontsize=13, fontweight='bold')


# magnitude response upper plot
ax = axes[0]
ax.plot(w_f, 20 * np.log10(np.abs(H_f) + 1e-12), 'b-',
        linewidth=1.5, label='Float')
ax.plot(w_i, 20 * np.log10(np.abs(H_i) + 1e-12), 'r--',
        linewidth=1.5, label=f'Q9 integer ({Q_SCALE}x)')
ax.axvspan(F_PASS1, F_PASS2, alpha=0.12, color='green', label='Passband target')
ax.axvspan(0, F_STOP1, alpha=0.12, color='red', label='Stopband (DC or motion)')
ax.axvspan(F_STOP2, nyq, alpha=0.12, color='red')
ax.axvline(F_PASS1, color='green', linestyle=':', linewidth=1)
ax.axvline(F_PASS2, color='green', linestyle=':', linewidth=1)
ax.set_xlabel('Frequency (Hz)')
ax.set_ylabel('Gain (dB)')
ax.set_ylim(-80, 10) # goal of +3dB gain
ax.set_xlim(0, nyq) # reflected after this point
ax.set_title('Magnitude Response')
ax.legend(loc='lower right', fontsize=9)
ax.grid(True, alpha=0.4)
ax.annotate('QRS band\n5-40 Hz', xy=(22, -2), xytext=(25, -15),
            fontsize=9, color='darkgreen',
            arrowprops=dict(arrowstyle='->', color='darkgreen'))


# coefficient values lower plot
ax2 = axes[1]
x = np.arange(N_TAPS)
ax2.stem(x, h_int, linefmt='b-', markerfmt='bo', basefmt='k-', # label the orignal Q9 filter taps
         label='Q9 integer coefficients')
ax2.stem(x, np.round(h_float * Q_SCALE), linefmt='r--', markerfmt='rx', # unrounded scaled floats
         basefmt='k-', label='Float * 512 (no rounding)')
ax2.axhline(0, color='k', linewidth=0.5)
for k, v in enumerate(h_int):
    ax2.annotate(str(v), (k, v), textcoords='offset points',
                 xytext=(0, 6 if v >= 0 else -12), ha='center', fontsize=8)
ax2.set_xlabel('Tap index k')
ax2.set_ylabel('Coefficient value')
ax2.set_title(f'Q9 Integer Coefficients  (symmetric: h[k] = h[{N_TAPS-1}-k])')
ax2.legend(fontsize=9)
ax2.grid(True, alpha=0.4)

plt.tight_layout()
plt.savefig('fir_response.png', dpi=150, bbox_inches='tight')
# print("\nFrequency response plot saved as fir_response.png")
plt.show()