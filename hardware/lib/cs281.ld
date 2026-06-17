/* =============================================================================
 * CS281 Virtual Development Board — Linker Script
 * RISC-V RV32IM
 *
 * Memory Layout
 * ─────────────────────────────────────────────────────────────────────────────
 *   ROM  0x20000000  256 KB   startup code, .text, .rodata
 *                             (loaded from ELF into Renode ROM peripheral)
 *   RAM  0x40000000  512 KB   .data (copied from ROM at boot), .bss, heap,
 *                             stack (grows down from top of RAM)
 *
 * Section placement
 * ─────────────────────────────────────────────────────────────────────────────
 *   .text.startup   → ROM first  (startup.S _start must be the entry point)
 *   .text           → ROM
 *   .rodata         → ROM
 *   .data           → LMA in ROM (stored after .rodata), VMA in RAM
 *                     startup.S copies LMA→VMA before calling main()
 *   .bss            → RAM only (zero-initialised by startup.S)
 *   stack           → top of RAM  (_stack_top symbol)
 *
 * Exported symbols used by startup.S
 *   _etext      — end of ROM content = LMA of .data
 *   _sdata      — VMA start of .data in RAM
 *   _edata      — VMA end   of .data in RAM
 *   _sbss       — start of .bss
 *   _ebss       — end   of .bss
 *   _stack_top  — initial stack pointer (top of RAM)
 * =============================================================================*/

ENTRY(_start)

MEMORY {
    ROM (rx)  : ORIGIN = 0x20000000, LENGTH = 256K
    RAM (rwx) : ORIGIN = 0x40000000, LENGTH = 512K
}

SECTIONS {

    /* ── ROM ──────────────────────────────────────────────────────────────── */

    .text : {
        /* startup.S must come first so _start is at 0x20000000 */
        KEEP(*(.text.startup))
        *(.text*)
        . = ALIGN(4);
    } > ROM

    .rodata : {
        *(.rodata*)
        . = ALIGN(4);
        _etext = .;     /* marks end of ROM content; also LMA of .data */
    } > ROM

    /* ── RAM ─────────────────────────────────────────────────────────────── */

    /* .data: stored in ROM immediately after .rodata (AT _etext = LMA),
     *        but runs at its VMA in RAM.  startup.S does the copy. */
    .data : AT(_etext) {
        _sdata = .;
        *(.data*)
        . = ALIGN(4);
        _edata = .;
    } > RAM

    /* .bss: zero-initialised variables, RAM only */
    .bss : {
        _sbss = .;
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } > RAM

    /* Stack pointer — initial value is the very top of RAM */
    _stack_top = ORIGIN(RAM) + LENGTH(RAM);

    /* Discard unused C-runtime sections */
    /DISCARD/ : {
        *(.eh_frame)
        *(.comment)
    }
}
