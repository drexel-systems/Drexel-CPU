/* CS281 board linker script for Zig
 *
 * ROM  0x20000000  256 KiB  — execute-in-place program ROM
 * RAM  0x40000000  512 KiB  — SRAM (stack, .data, .bss)
 *
 * Simpler than the riscv-rt approach: no REGION_ALIAS needed because
 * this script places sections directly rather than via abstract names.
 */

ENTRY(_start)

MEMORY {
    ROM (rx)  : ORIGIN = 0x20000000, LENGTH = 256K
    RAM (rwx) : ORIGIN = 0x40000000, LENGTH = 512K
}

SECTIONS {
    /* _start must be the very first instruction executed at ROM base. */
    .text 0x20000000 : {
        KEEP(*(.text._start))
        *(.text .text.*)
        *(.rodata .rodata.*)
        . = ALIGN(4);
    } > ROM

    _etext = .;

    /* .data: stored in ROM (LMA = _sidata), runs from RAM (VMA = _sdata). */
    .data : AT(_etext) {
        _sdata  = .;
        *(.data .data.*)
        . = ALIGN(4);
        _edata  = .;
    } > RAM

    _sidata = LOADADDR(.data);

    /* .bss: zero-initialised, RAM only. */
    .bss (NOLOAD) : {
        _sbss = .;
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } > RAM

    /* Stack grows down from the top of RAM. */
    _stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
