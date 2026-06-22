/* CS281 board memory map for riscv-rt
 *
 * Step 1: define the physical memory regions.
 * Step 2: map riscv-rt's abstract REGION_* names to those regions.
 *
 * riscv-rt's link.x uses REGION_TEXT, REGION_RODATA, REGION_DATA, REGION_BSS,
 * REGION_HEAP, and REGION_STACK throughout its SECTIONS block — it never
 * references ROM or RAM directly.  The REGION_ALIAS directives below are the
 * bridge between our board's layout and the crate's linker script.
 */

MEMORY {
    ROM (rx)  : ORIGIN = 0x20000000, LENGTH = 256K
    RAM (rwx) : ORIGIN = 0x40000000, LENGTH = 512K
}

REGION_ALIAS("REGION_TEXT",   ROM);
REGION_ALIAS("REGION_RODATA", ROM);
REGION_ALIAS("REGION_DATA",   RAM);
REGION_ALIAS("REGION_BSS",    RAM);
REGION_ALIAS("REGION_HEAP",   RAM);
REGION_ALIAS("REGION_STACK",  RAM);
