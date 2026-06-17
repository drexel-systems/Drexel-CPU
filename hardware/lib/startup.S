/* =============================================================================
 * CS281 Virtual Development Board — Startup / Reset Handler
 * File: hardware/lib/startup.S
 *
 * This file is the very first thing that executes after reset.  The linker
 * script (cs281.ld) places .text.startup at the start of ROM (0x20000000),
 * so _start lands at that address.  Renode's ELF loader sets the CPU PC to
 * the ELF entry point, which the linker resolves to _start.
 *
 * Responsibilities
 *   1. Set the stack pointer (sp) to _stack_top (top of RAM).
 *   2. Copy the .data segment from ROM (LMA) to RAM (VMA).
 *   3. Zero-initialise the .bss segment.
 *   4. Call main().
 *   5. If main() returns (it shouldn't), spin forever.
 *
 * Symbols provided by cs281.ld:
 *   _etext     — end of ROM content = source (LMA) of .data
 *   _sdata     — destination start (VMA) of .data in RAM
 *   _edata     — destination end   (VMA) of .data in RAM
 *   _sbss      — start of .bss
 *   _ebss      — end   of .bss
 *   _stack_top — top of RAM (initial sp)
 * =============================================================================*/

    .section .text.startup      /* must be first; linker script keeps this */
    .globl  _start
    .type   _start, @function

_start:
    /* ── 1. Initialise stack pointer ──────────────────────────────────────── */
    la      sp, _stack_top

    /* ── 2. Copy .data from ROM (LMA = _etext) to RAM (VMA = _sdata…_edata) ─
     *
     *   t0 = read  pointer (ROM LMA)
     *   t1 = write pointer (RAM VMA)
     *   t2 = end of RAM VMA region
     */
    la      t0, _etext          /* ROM source  */
    la      t1, _sdata          /* RAM dest    */
    la      t2, _edata          /* RAM end     */

.Lcopy_data:
    beq     t1, t2, .Lzero_bss  /* nothing left to copy? */
    lw      t3, 0(t0)
    sw      t3, 0(t1)
    addi    t0, t0, 4
    addi    t1, t1, 4
    j       .Lcopy_data

    /* ── 3. Zero .bss ─────────────────────────────────────────────────────── */
.Lzero_bss:
    la      t0, _sbss
    la      t1, _ebss

.Lzero_loop:
    beq     t0, t1, .Lcall_main
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       .Lzero_loop

    /* ── 4. Call main ─────────────────────────────────────────────────────── */
.Lcall_main:
    call    main                /* main() should never return */

    /* ── 5. Hang if main() returns ────────────────────────────────────────── */
.Lhalt:
    j       .Lhalt
    .size   _start, . - _start
