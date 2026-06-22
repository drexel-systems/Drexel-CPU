// =============================================================================
// CS281 Lab 5 (Rust) — build.rs
//
// riscv-rt 0.12 does NOT auto-emit any -T flags.  We must pass them ourselves:
//
//   -Tmemory.x   our file: defines MEMORY{ROM,RAM} + REGION_ALIAS for all
//                the abstract REGION_* names that riscv-rt's link.x uses.
//
//   -Tlink.x     riscv-rt's file: full SECTIONS layout, symbol PROVIDEs,
//                startup hooks (__pre_init, _mp_hook, _setup_interrupts …).
//                It lives in riscv-rt's OUT_DIR, which riscv-rt's own
//                build script already adds to the linker search path.
//
// Order matters: memory.x must be processed before link.x so that the
// MEMORY regions and REGION_ALIAS are visible when link.x's SECTIONS run.
// =============================================================================

use std::fs;
use std::path::PathBuf;

fn main() {
    let out_dir = PathBuf::from(std::env::var("OUT_DIR").unwrap());

    // Copy memory.x to OUT_DIR so the linker can find it via the -L search path.
    fs::copy("memory.x", out_dir.join("memory.x")).unwrap();
    println!("cargo:rustc-link-search={}", out_dir.display());

    // 1. Apply memory.x first — defines MEMORY{} and REGION_ALIAS.
    println!("cargo:rustc-link-arg=-Tmemory.x");
    // 2. Apply riscv-rt's link.x second — uses REGION_* to place sections.
    println!("cargo:rustc-link-arg=-Tlink.x");

    println!("cargo:rerun-if-changed=memory.x");
    println!("cargo:rerun-if-changed=build.rs");
}
