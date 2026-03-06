# 128-Point-Pipelined-FFT-on-FPGA
A fully pipelined 128-point complex FFT implementation in Verilog, based on the open-source ZipCPU pipelined FFT generator by Dan Gisselquist (Gisselquist Technology, LLC). The design uses Radix-2 Decimation-In-Frequency (DIF), hardware DSP multipliers, and is verified via ModelSim simulation and MATLAB DIF cross-validation.
