import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


# ============================================================
# Tiny Tapeout pin definitions
# ============================================================

EXT_CLK       = 0
OUTPUT_ENABLE = 1
START         = 2
IMAGE_WE      = 3
WEIGHT_WE     = 4

BUSY_BIT = 6
DONE_BIT = 7


# ============================================================
# CNN parameters
# ============================================================

H = 8
W = 8

KH = 3
KW = 3

OH = 6
OW = 6

NUM_IMAGE = 64
NUM_KERNEL = 9
NUM_OUTPUT = 36


# ============================================================
# Helpers
# ============================================================

def to_u8(value):
    """
    Convert signed/unsigned integer to 8-bit two's complement.
    """
    return value & 0xFF


def get_uo(dut):
    return int(dut.uo_out.value)


def read_output(dut):
    """
    Physical CNN result is uo_out[5:0].
    """
    return get_uo(dut) & 0x3F


def read_busy(dut):
    return (get_uo(dut) >> BUSY_BIT) & 1


def read_done(dut):
    return (get_uo(dut) >> DONE_BIT) & 1


# ============================================================
# Reset
# ============================================================

async def reset_dut(dut):

    dut.ena.value = 0
    dut.rst_n.value = 0

    dut.ui_in.value = 0
    dut.uio_in.value = 0

    # Five clock cycles in reset
    for _ in range(5):
        await RisingEdge(dut.clk)

    dut.rst_n.value = 1

    # Three clocks after reset
    for _ in range(3):
        await RisingEdge(dut.clk)

    dut.ena.value = 1

    # Allow enable to propagate
    for _ in range(2):
        await RisingEdge(dut.clk)


# ============================================================
# Write image value
# ============================================================

async def write_image(dut, value):

    dut.ui_in.value = to_u8(value)

    uio = int(dut.uio_in.value)
    uio |= (1 << IMAGE_WE)
    dut.uio_in.value = uio

    await RisingEdge(dut.clk)

    uio = int(dut.uio_in.value)
    uio &= ~(1 << IMAGE_WE)
    dut.uio_in.value = uio

    await RisingEdge(dut.clk)


# ============================================================
# Write kernel value
# ============================================================

async def write_weight(dut, value):

    dut.ui_in.value = to_u8(value)

    uio = int(dut.uio_in.value)
    uio |= (1 << WEIGHT_WE)
    dut.uio_in.value = uio

    await RisingEdge(dut.clk)

    uio = int(dut.uio_in.value)
    uio &= ~(1 << WEIGHT_WE)
    dut.uio_in.value = uio

    await RisingEdge(dut.clk)


# ============================================================
# Upload image
# ============================================================

async def upload_image(dut, image):

    print()
    print("--------------------------------------------")
    print("UPLOADING 8x8 IMAGE")
    print("--------------------------------------------")

    for value in image:
        await write_image(dut, value)

    print("Image upload complete.")


# ============================================================
# Upload kernel
# ============================================================

async def upload_kernel(dut, kernel):

    print()
    print("--------------------------------------------")
    print("UPLOADING 3x3 KERNEL")
    print("--------------------------------------------")

    for value in kernel:
        await write_weight(dut, value)

    print("Kernel upload complete.")


# ============================================================
# Start CNN
# ============================================================

async def start_cnn(dut):

    uio = int(dut.uio_in.value)
    uio |= (1 << START)
    dut.uio_in.value = uio

    await RisingEdge(dut.clk)

    uio = int(dut.uio_in.value)
    uio &= ~(1 << START)
    dut.uio_in.value = uio

    await RisingEdge(dut.clk)


# ============================================================
# Wait for BUSY
# ============================================================

async def wait_for_busy(dut, timeout=20000):

    for _ in range(timeout):

        if read_busy(dut) == 1:
            print("BUSY = 1")
            return

        await RisingEdge(dut.clk)

    raise AssertionError("BUSY timeout")


# ============================================================
# Wait for DONE
# ============================================================

async def wait_for_done(dut, timeout=20000):

    for _ in range(timeout):

        if read_done(dut) == 1:
            print("DONE = 1")
            return

        await RisingEdge(dut.clk)

    raise AssertionError("DONE timeout")


# ============================================================
# Calculate software reference
# ============================================================

def calculate_expected(image, kernel):

    expected = []

    for r in range(OH):

        for c in range(OW):

            total = 0

            for kr in range(KH):

                for kc in range(KW):

                    image_index = (r + kr) * W + (c + kc)
                    kernel_index = kr * KW + kc

                    total += (
                        image[image_index]
                        * kernel[kernel_index]
                    )

            # Physical output is only 6 bits
            expected.append(total & 0x3F)

    return expected


# ============================================================
# Print image
# ============================================================

def print_image(image):

    print()
    print("INPUT IMAGE:")

    for r in range(H):

        row = image[r * W:(r + 1) * W]

        print("  " + "".join(f"{x:6d}" for x in row))


# ============================================================
# Print kernel
# ============================================================

def print_kernel(kernel):

    print()
    print("KERNEL:")

    for r in range(KH):

        row = kernel[r * KW:(r + 1) * KW]

        print("  " + "".join(f"{x:6d}" for x in row))


# ============================================================
# Print expected
# ============================================================

def print_expected(expected):

    print()
    print("EXPECTED 6x6 OUTPUT:")

    for r in range(OH):

        row = expected[r * OW:(r + 1) * OW]

        print(
            f"  Row {r}: "
            + "".join(f"{x:6d}" for x in row)
        )


# ============================================================
# Read outputs using internal clock
# ============================================================

async def read_internal_clock(dut):

    print()
    print("--------------------------------------------")
    print("READING OUTPUT USING INTERNAL CLOCK")
    print("--------------------------------------------")

    # Output controller uses internal clk
    uio = int(dut.uio_in.value)

    uio &= ~(1 << OUTPUT_ENABLE)
    uio &= ~(1 << EXT_CLK)

    dut.uio_in.value = uio

    actual = [0] * NUM_OUTPUT

    # Result 0 is already visible when DONE is active.
    await Timer(1, units="ns")

    actual[0] = read_output(dut)

    # Every following system clock advances output index.
    for j in range(1, NUM_OUTPUT):

        await RisingEdge(dut.clk)
        await Timer(1, units="ns")

        actual[j] = read_output(dut)

    print("Internal-clock read complete.")

    return actual


# ============================================================
# Read outputs using external clock
# ============================================================

async def read_external_clock(dut):

    print()
    print("--------------------------------------------")
    print("READING OUTPUT USING EXTERNAL CLOCK")
    print("--------------------------------------------")

    uio = int(dut.uio_in.value)

    # Enable external clock mode
    uio |= (1 << OUTPUT_ENABLE)

    # External clock starts LOW
    uio &= ~(1 << EXT_CLK)

    dut.uio_in.value = uio

    # Give DUT time to see mode change
    for _ in range(4):
        await RisingEdge(dut.clk)

    actual = [0] * NUM_OUTPUT

    await Timer(1, units="ns")

    actual[0] = read_output(dut)

    for j in range(1, NUM_OUTPUT):

        # Make sure EXT_CLK is LOW
        uio = int(dut.uio_in.value)
        uio &= ~(1 << EXT_CLK)
        dut.uio_in.value = uio

        for _ in range(2):
            await RisingEdge(dut.clk)

        # ----------------------------------------------------
        # Rising edge of external clock
        # ----------------------------------------------------

        uio = int(dut.uio_in.value)
        uio |= (1 << EXT_CLK)
        dut.uio_in.value = uio

        # Allow external-clock event to propagate
        for _ in range(4):
            await RisingEdge(dut.clk)

        # ----------------------------------------------------
        # Return external clock LOW
        # ----------------------------------------------------

        uio = int(dut.uio_in.value)
        uio &= ~(1 << EXT_CLK)
        dut.uio_in.value = uio

        for _ in range(2):
            await RisingEdge(dut.clk)

        await Timer(1, units="ns")

        actual[j] = read_output(dut)

    # Return to normal state
    uio = int(dut.uio_in.value)
    uio &= ~(1 << EXT_CLK)
    uio &= ~(1 << OUTPUT_ENABLE)
    dut.uio_in.value = uio

    for _ in range(4):
        await RisingEdge(dut.clk)

    print("External-clock read complete.")

    return actual


# ============================================================
# Check results
# ============================================================

def check_results(name, actual, expected):

    errors = []

    for i in range(NUM_OUTPUT):

        if actual[i] != expected[i]:

            errors.append(
                (
                    i,
                    expected[i],
                    actual[i]
                )
            )

    if len(errors) == 0:

        print()
        print(f"{name}: PASS - 36/36")

    else:

        print()
        print(
            f"{name}: FAIL - "
            f"{len(errors)}/36 incorrect"
        )

        for index, exp, got in errors:

            print(
                f"  output[{index}]: "
                f"expected={exp}, got={got}"
            )

    return len(errors) == 0


# ============================================================
# Print matrices
# ============================================================

def print_output_matrices(
    expected,
    internal,
    external
):

    print()
    print("=" * 62)
    print("OUTPUT MATRICES")
    print("=" * 62)

    print()
    print("EXPECTED:")

    for r in range(OH):

        row = expected[r * OW:(r + 1) * OW]

        print("  " + "".join(f"{x:6d}" for x in row))

    print()
    print("INTERNAL CLOCK:")

    for r in range(OH):

        row = internal[r * OW:(r + 1) * OW]

        print("  " + "".join(f"{x:6d}" for x in row))

    print()
    print("EXTERNAL CLOCK:")

    for r in range(OH):

        row = external[r * OW:(r + 1) * OW]

        print("  " + "".join(f"{x:6d}" for x in row))

    print()
    print("SIDE-BY-SIDE:")
    print()
    print(
        "       EXPECTED"
        "                         INTERNAL CLK"
        "                      EXTERNAL CLK"
    )

    for r in range(OH):

        exp = expected[r * OW:(r + 1) * OW]
        inte = internal[r * OW:(r + 1) * OW]
        ext = external[r * OW:(r + 1) * OW]

        print(
            f"Row {r}: "
            + "".join(f"{x:4d}" for x in exp)
            + "       "
            + "".join(f"{x:4d}" for x in inte)
            + "       "
            + "".join(f"{x:4d}" for x in ext)
        )


# ============================================================
# TEST 1
# ============================================================

def setup_mixed_test():

    image = [
         3,  7, 12,  5,  9, 14,  2,  8,
        16,  4, 11, 20,  6, 13, 18,  1,
        10, 22,  5, 17,  8,  3, 15, 19,
         6, 14, 21,  2, 16,  7, 11, 23,
        18,  9,  4, 25, 13, 20,  5, 12,
         7, 15, 24,  6, 10,  2, 17,  9,
        11,  3,  8, 19, 22, 14,  4, 16,
         5, 13, 20,  7,  1, 18,  9, 21,
    ]

    kernel = [
         2, -1,  3,
         1,  2, -2,
         3,  1, -1,
    ]

    return image, kernel


# ============================================================
# TEST 2: +127 / +127
# ============================================================

def setup_positive_extreme():

    image = [127] * NUM_IMAGE
    kernel = [127] * NUM_KERNEL

    return image, kernel


# ============================================================
# TEST 3: -128 / +127
# ============================================================

def setup_negative_extreme():

    image = [-128] * NUM_IMAGE
    kernel = [127] * NUM_KERNEL

    return image, kernel


# ============================================================
# TEST 4: -128 / -128
# ============================================================

def setup_min_min():

    image = [-128] * NUM_IMAGE
    kernel = [-128] * NUM_KERNEL

    return image, kernel


# ============================================================
# Run one complete test
# ============================================================

async def run_test(dut, image, kernel):

    expected = calculate_expected(image, kernel)

    await reset_dut(dut)

    await upload_image(dut, image)

    await upload_kernel(dut, kernel)

    await start_cnn(dut)

    await wait_for_busy(dut)

    await wait_for_done(dut)

    internal = await read_internal_clock(dut)

    external = await read_external_clock(dut)

    print_output_matrices(
        expected,
        internal,
        external
    )

    internal_pass = check_results(
        "INTERNAL CLOCK",
        internal,
        expected
    )

    external_pass = check_results(
        "EXTERNAL CLOCK",
        external,
        expected
    )

    return internal_pass and external_pass


# ============================================================
# Main Cocotb test
# ============================================================

@cocotb.test()
async def test_cnn_accelerator(dut):

    # --------------------------------------------------------
    # Start 100 MHz clock
    # 10 ns period = 100 MHz
    # --------------------------------------------------------

    cocotb.start_soon(
        Clock(dut.clk, 10, units="ns").start()
    )

    # --------------------------------------------------------
    # Initial values
    # --------------------------------------------------------

    dut.ena.value = 0
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0

    # --------------------------------------------------------
    # TEST 1
    # --------------------------------------------------------

    print()
    print("############################################")
    print("# TEST 1: MIXED SIGNED DATA")
    print("############################################")

    image, kernel = setup_mixed_test()

    print_image(image)
    print_kernel(kernel)

    expected = calculate_expected(image, kernel)
    print_expected(expected)

    result = await run_test(
        dut,
        image,
        kernel
    )

    assert result, "TEST 1 FAILED"

    # --------------------------------------------------------
    # TEST 2
    # --------------------------------------------------------

    print()
    print("############################################")
    print("# TEST 2: +127 / +127")
    print("############################################")

    image, kernel = setup_positive_extreme()

    print_image(image)
    print_kernel(kernel)

    expected = calculate_expected(image, kernel)
    print_expected(expected)

    result = await run_test(
        dut,
        image,
        kernel
    )

    assert result, "TEST 2 FAILED"

    # --------------------------------------------------------
    # TEST 3
    # --------------------------------------------------------

    print()
    print("############################################")
    print("# TEST 3: -128 / +127")
    print("############################################")

    image, kernel = setup_negative_extreme()

    print_image(image)
    print_kernel(kernel)

    expected = calculate_expected(image, kernel)
    print_expected(expected)

    result = await run_test(
        dut,
        image,
        kernel
    )

    assert result, "TEST 3 FAILED"

    # --------------------------------------------------------
    # TEST 4
    # --------------------------------------------------------

    print()
    print("############################################")
    print("# TEST 4: -128 / -128")
    print("############################################")

    image, kernel = setup_min_min()

    print_image(image)
    print_kernel(kernel)

    expected = calculate_expected(image, kernel)
    print_expected(expected)

    result = await run_test(
        dut,
        image,
        kernel
    )

    assert result, "TEST 4 FAILED"

    # --------------------------------------------------------
    # Complete
    # --------------------------------------------------------

    print()
    print("============================================")
    print("      CNN ACCELERATOR TEST COMPLETE")
    print("============================================")
    print()
    print("Verified through Tiny Tapeout pins:")
    print()
    print("  ui_in[7:0]    = image / weight data")
    print("  uio_in[0]     = external clock")
    print("  uio_in[1]     = output enable")
    print("  uio_in[2]     = start")
    print("  uio_in[3]     = image write enable")
    print("  uio_in[4]     = weight write enable")
    print("  uo_out[5:0]   = result")
    print("  uo_out[6]     = busy")
    print("  uo_out[7]     = done")
    print()
    print("No hierarchical/internal DUT signals were accessed.")
    print()

    await Timer(100, units="ns")
