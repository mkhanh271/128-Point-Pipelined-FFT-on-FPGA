# 128-Point Pipelined FFT on FPGA (Verilog + MATLAB Verification)

> A fully pipelined **128-point complex FFT** implementation in Verilog, based on the open-source [ZipCPU pipelined FFT generator](https://github.com/ZipCPU/dblclockfft) by Dan Gisselquist (Gisselquist Technology, LLC). The design uses **Radix-2 Decimation-In-Frequency (DIF)**, hardware DSP multipliers, and is verified via **ModelSim simulation** and **MATLAB DIF cross-validation**.

---
## This is my group project - i only do the MATLAB and verilog simulation , for Implemenation on FPGA it will be updated in the future when i ask my friends :)) , and all the other files code are in [ZipCPU pipelined FFT generator](https://github.com/ZipCPU/dblclockfft)

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Project Structure](#project-structure)
- [Pipeline Stages](#pipeline-stages)
- [Simulation: ModelSim](#simulation-modelsim)
- [Verification: MATLAB](#verification-matlab)
- [Key Parameters](#key-parameters)
- [References](#references)

---

## Overview

This project implements a **128-point pipelined FFT** with the following properties:

| Property | Value |
|---|---|
| FFT Size | 128 points |
| Algorithm | Radix-2 Decimation-In-Frequency (DIF) |
| Input width | 8-bit real + 8-bit imaginary = 16 bits |
| Output width | 8-bit real + 8-bit imaginary = 16 bits |
| Twiddle factor width | 12–14 bits (from `.hex` coefficient files) |
| Throughput | 1 complex sample per clock cycle |
| Clock | 100 MHz (10 ns period, from testbench) |
| Hardware multipliers | Yes — DSP blocks used for 5 of 7 stages |
| Stages | 7 pipeline stages (128 → 64 → 32 → 16 → 8 → 4 → 2 → bit-reversal) |

The FFT is **fully pipelined**: it accepts one complex sample per clock and produces one complex output per clock after the initial pipeline fill latency.

---

## Architecture

```
                     ┌─────────────────────────────────────────────────┐
  i_sample[15:0]     │                    fftmain.v                     │    o_result[15:0]
  {Re[7:0],Im[7:0]}  │                                                  │    {Re[7:0],Im[7:0]}
 ──────────────────► │  stage_128 → stage_64 → stage_32 → stage_16     │ ──────────────────►
                     │      → stage_8 → stage_4 → stage_2              │
  i_clk, i_ce        │                     → bitreverse                 │    o_sync
  i_reset            │                                                  │
                     └─────────────────────────────────────────────────┘
```

### Module Hierarchy

```
fftmain.v                        ← Top-level: chains all stages
├── fftstage.v  × 5              ← General butterfly stage (stages 128–8, uses DSP)
│   ├── butterfly.v              ← Complex butterfly with twiddle multiply
│   │   ├── longbimpy.v          ← Long-word multiplier
│   │   └── bimpy.v              ← Base multiplier primitive
│   ├── hwbfly.v                 ← Hardware-accelerated butterfly (OPT_HWMPY=1)
│   └── convround.v              ← Convergent rounding
├── qtrstage.v                   ← Quarter-stage butterfly (stage 4, ×j twiddles)
├── laststage.v                  ← Final butterfly stage (stage 2, trivial twiddles)
└── bitreverse.v                 ← Bit-reversal reordering of output
```

### Twiddle Factor Coefficient Files

Pre-computed twiddle factors are stored as fixed-point hex values and loaded at synthesis:

| File | Used by Stage | Twiddle Count |
|------|--------------|---------------|
| `cmem_128.hex` | stage_128 (span=64) | 64 |
| `cmem_64.hex` | stage_64 (span=32) | 32 |
| `cmem_32.hex` | stage_32 (span=16) | 16 |
| `cmem_16.hex` | stage_16 (span=8) | 8 |
| `cmem_8.hex` | stage_8 (span=4) | 4 |

---

## Project Structure

```
.
├── fftmain.v                  # Top-level FFT module (128-point, fully pipelined)
├── fftmain_tb.v               # ModelSim testbench: feeds input, captures output
├── fftstage.v                 # General pipelined FFT stage (DSP-accelerated)
├── butterfly.v                # Complex butterfly unit
├── hwbfly.v                   # Hardware multiplier butterfly (OPT_HWMPY=1)
├── longbimpy.v                # Long-word multiplier
├── bimpy.v                    # Base multiplier primitive
├── qtrstage.v                 # Quarter-stage (×j twiddle factors)
├── laststage.v                # Last stage (trivial twiddle = ±1)
├── bitreverse.v               # Bit-reversal permutation stage
├── convround.v                # Convergent rounding module
├── cmem_8.hex                 # Twiddle coefficients for stage_8
├── cmem_16.hex                # Twiddle coefficients for stage_16
├── cmem_32.hex                # Twiddle coefficients for stage_32
├── cmem_64.hex                # Twiddle coefficients for stage_64
├── cmem_128.hex               # Twiddle coefficients for stage_128
├── DIF.m                      # MATLAB: FFT DIF algorithm + hardware cross-validation
├── plot_fft_result.m          # MATLAB: visualize input/output spectra
└── README.md
```

---

## Pipeline Stages

The 128-point FFT = log₂(128) = **7 stages**, chained as follows:

| Stage | Module | LGSPAN | Input Width | Output Width | Multiplier |
|-------|--------|--------|-------------|--------------|------------|
| 128 | `fftstage` | 6 (span=64) | 8-bit | 10-bit | DSP (OPT_HWMPY=1) |
| 64 | `fftstage` | 5 (span=32) | 10-bit | 10-bit | DSP |
| 32 | `fftstage` | 4 (span=16) | 10-bit | 10-bit | DSP |
| 16 | `fftstage` | 3 (span=8) | 10-bit | 10-bit | DSP |
| 8 | `fftstage` | 2 (span=4) | 10-bit | 10-bit | DSP |
| 4 | `qtrstage` | — | 10-bit | 10-bit | Shift only (×j) |
| 2 | `laststage` | — | 10-bit | 8-bit | Add/Sub only |
| — | `bitreverse` | LGSIZE=7 | 8-bit | 8-bit | — |

> **Note:** Bit-width grows from 8 to 10 bits at stage_128 to absorb potential overflow during butterfly addition, then is rounded back to 8 bits at `laststage` using convergent rounding.

---

## Simulation: ModelSim

### What the testbench does (`fftmain_tb.v`)

1. **Reset** the FFT core for 100 ns
2. **Feed 128 random complex samples** (8-bit signed real + imaginary), one per clock at 100 MHz
3. Log all 128 input samples to `fft_input_complex.txt`
4. **Wait for `o_sync`** — the output valid flag that marks the first output sample
5. **Capture 128 complex output samples** to `fft_output_complex.txt`
6. Dump waveform to `fft_wave.vcd` for inspection

### File I/O

| File | Format | Description |
|------|--------|-------------|
| `fft_input_complex.txt` | `Re Im` per line (signed decimal) | 128 input samples written by testbench |
| `fft_output_complex.txt` | `Re Im` per line (signed decimal) | 128 FFT output samples captured by testbench |
| `fft_wave.vcd` | VCD waveform | Full signal dump for GTKWave or ModelSim |

### Running in ModelSim

```tcl
# In ModelSim console (or .do script)

# 1. Create and map library
vlib work
vmap work work

# 2. Compile all Verilog sources
vlog fftmain.v fftstage.v butterfly.v hwbfly.v bimpy.v longbimpy.v \
     convround.v qtrstage.v laststage.v bitreverse.v fftmain_tb.v

# 3. Start simulation
vsim -t ns fftmain_tb

# 4. Add waves and run
add wave -r /*
run -all
```

After simulation completes, `fft_input_complex.txt` and `fft_output_complex.txt` will be generated in the working directory.

---

## Verification: MATLAB

Two MATLAB scripts are provided to visualize and cross-validate the hardware output.

### `DIF.m` — Reference Implementation + Hardware Comparison

Implements the full **Radix-2 DIF FFT algorithm in MATLAB** and compares it against the hardware output from ModelSim:

```
[1/7] Load input from fft_input_complex.txt
[2/7] Compute twiddle factors W = exp(-j2πk/N)
[3/7] Run DIF butterfly algorithm (7 stages)
[4/7] Bit-reversal output reordering
[5/7] Fixed-point conversion (8-bit, scale by 1/N)
[6/7] Compare MATLAB vs Hardware (fft_output_complex.txt)
[7/7] Plot results (3 figures)
```

**Comparison metrics output:**

```
Max error (Real)   : 0–1 (expected — due to fixed-point rounding)
Max error (Imag)   : 0–1
Perfect matches    : ~95–100% of 128 points
```

**Figures generated:**

| Figure | Content |
|--------|---------|
| Figure 1 | Input signal: Real part, Imaginary part, Magnitude (time domain) |
| Figure 2 | FFT output: Magnitude spectrum + Phase spectrum with dominant frequency labels |
| Figure 3 | Hardware vs MATLAB: Real/Imag comparison, error plots, magnitude overlay, error histogram |

---

### `plot_fft_result.m` — Standalone Output Visualization

Reads `fft_input_complex.txt` and `fft_output_complex.txt` directly and plots:
- Input signal (real, imaginary, magnitude) over 128 samples
- FFT magnitude spectrum with dominant frequency bins highlighted in red

---

### Full Workflow

```
1. Run ModelSim simulation (fftmain_tb.v)
        ↓ generates
   fft_input_complex.txt
   fft_output_complex.txt

2. Run MATLAB:  DIF.m
        ↓ produces
   Figure 1 — Input time-domain signal
   Figure 2 — FFT output spectrum
   Figure 3 — Hardware vs MATLAB comparison
   matlab_fft_output.txt

3. (Optional) Run MATLAB: plot_fft_result.m
        ↓ produces
   Additional input/output visualization
```

---

## Key Parameters

| Parameter | Value | Description |
|---|---|---|
| `FFT_SIZE` | 128 | Number of complex points |
| `IWIDTH` | 8 | Input bit width (per component) |
| `OWIDTH` | 8 | Output bit width (per component) |
| `CWIDTH` | 12–14 | Coefficient (twiddle) bit width |
| `OPT_HWMPY` | 1 | Use hardware DSP multipliers |
| `CKPCE` | 1 | Clocks per clock enable (pipeline rate) |
| `BFLYSHIFT` | 0 | Bit-shift at butterfly output |
| Clock | 100 MHz | From testbench `always #5 clk = ~clk` |

---

## References

- Dan Gisselquist — *An Open Source Pipelined FFT Generator*, Oct 2018, [ZipCPU Blog](https://zipcpu.com/dsp/2018/10/02/fft.html)
- [dblclockfft — GitHub (ZipCPU)](https://github.com/ZipCPU/dblclockfft)
- Cooley, J.W. & Tukey, J.W. — *"An Algorithm for the Machine Calculation of Complex Fourier Series"*, Mathematics of Computation, 1965
- OpenCores DSP library — [opencores.org](https://opencores.org)

---

## License

The Verilog RTL sources (`fftmain.v`, `fftstage.v`, etc.) are derived from the ZipCPU pipelined FFT project and are licensed under the **GNU Lesser General Public License v3 (LGPL-3.0)**.

The MATLAB scripts (`DIF.m`, `plot_fft_result.m`) and testbench (`fftmain_tb.v`) are original work released under the **MIT License**.
