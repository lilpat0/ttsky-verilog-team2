## How it works

This project implements a hardware accelerator for performing a 3x3 convolution on an 8x8 input image using the IM2COL method.

The accelerator contains separate memories for the input image and the convolution weights. The image consists of 64 8-bit values and the 3x3 kernel consists of 9 8-bit values. The image and kernel share the same 8-bit input data bus, with separate write-enable signals selecting which memory receives each value.

After all 64 image values and 9 kernel values have been loaded, the accelerator can be started. The IM2COL image provider generates the input values required for each convolution window. A matrix-multiplication sequencer controls the multiply-accumulate operations, and the MAC unit calculates the convolution results.

An 8x8 input with a 3x3 kernel and no padding produces a 6x6 output, giving 36 output values. The results are stored internally so that they can be read after the accelerator finishes.

## How to test

First, reset the accelerator using the active-low `rst_n` signal and enable the design using `ena`.

### Loading the image

The 8x8 image is loaded using the `input_data[7:0]` bus and `image_write_enable`.

Set `image_write_enable` high while `weight_write_enable` is low, place an 8-bit image value on `input_data`, and provide a clock cycle. The internal image address automatically increments after each write.

Repeat this process 64 times to load the complete 8x8 image. The image values are loaded in sequential address order from address 0 through address 63.

### Loading the kernel

The 3x3 convolution kernel is loaded using the same `input_data[7:0]` bus, but with `weight_write_enable` asserted instead.

Set `weight_write_enable` high while `image_write_enable` is low, place an 8-bit kernel value on `input_data`, and provide a clock cycle.

Repeat this process 9 times to load the complete 3x3 kernel. The kernel values are loaded in sequential address order from address 0 through address 8.

Image and weight writes should not be performed simultaneously.

### Starting the convolution

After all 64 image values and all 9 kernel values have been loaded, assert `start`. The accelerator detects the rising edge of `start` and begins the convolution.

The `busy` output indicates that the accelerator is processing. The `start` signal should only be asserted after both the image and kernel have been completely loaded.

When processing is complete, `done` is asserted.

### Reading the results

The accelerator produces 36 results corresponding to the 6x6 output of the 8x8 image convolved with the 3x3 kernel.

When `done` is high, the result at the current output index is available on `output_data[5:0]`.

With `ext_output_enable` low, the internal output index automatically advances through the stored results. With `ext_output_enable` high, the external `ext_clk` signal is used to advance the output index.

The current hardware exposes the lower 6 bits of each 20-bit accumulated result on `output_data`. Therefore, each of the 36 results is read as a 6-bit value.

The included Cocotb testbench loads the image and kernel, starts the accelerator, waits for `done`, reads the calculated results, and compares them against the expected convolution results.

## External hardware

No external hardware is required. The accelerator uses the Tiny Tapeout digital I/O interface.
