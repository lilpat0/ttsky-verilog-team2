## How It Works
Developed as part of the **MIT Beaver Works Summer Institute (BWSI) Basics of ASICs program**, this project implements a hardware accelerator that performs 3×3 convolution on an 8×8 image using the IM2COL method.

<img width="738" height="210" alt="image" src="https://github.com/user-attachments/assets/77c271d0-396f-400c-9ad0-d7e23e99d4ad" />


The accelerator stores the image (64 8-bit pixels) and convolution kernel (9 8-bit weights) in separate memories. An IM2COL image provider, matrix multiplication sequencer, and multiply-accumulate (MAC) unit work together to calculate the convolution.

The resulting 6×6 output contains 36 values, which are stored internally and can be read once processing is complete. The design exposes the lower 6 bits of each accumulated result through its output interface.

## How to Test

After resetting the accelerator, load the 64 image values and 9 kernel weights through the shared 8-bit input bus using their respective write-enable signals. Once both memories are loaded, assert `start` to begin computation.

The `busy` signal indicates active processing, and `done` signals completion. The 36 results can then be read through `output_data`, using either the internal output clock or the external `ext_clk` interface.

An included Cocotb testbench automates memory loading, starts the accelerator, reads the results, and verifies them against expected convolution values.

**No external hardware is required.** The accelerator uses the Tiny Tapeout digital I/O interface.

For additional implementation details, testing instructions, and documentation, see [`docs/info.md`](docs/info.md).
