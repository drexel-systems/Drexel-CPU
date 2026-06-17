/* =============================================================================
 * CS281 — exit()
 * File: hardware/lib/exit.S
 *
 * Cleanly terminates a bare-metal program.
 *
 * On a real CPU there is no operating system to "return to" — if main()
 * returns or the program falls off the end, the CPU keeps fetching and
 * executing whatever bytes happen to follow in memory.  exit() makes the
 * intended stop point explicit:
 *
 *   1. Global interrupts are disabled so nothing can fire after this point.
 *   2. A message is sent over UART so you can see when and why execution
 *      stopped.
 *   3. The CPU spins with WFI (Wait For Interrupt).  Since MIE is cleared,
 *      no interrupt can wake it — the core idles at essentially zero
 *      simulation cost in Renode.
 *
 * Usage
 *   call  exit      — standard call (never returns)
 *   j     exit      — tail-call variant (saves one stack frame, also fine)
 *
 * Clobbers: a0, t0 (irrelevant — this function never returns)
 * =============================================================================*/

    .section .rodata
.Lstr_halted:
    .string "\r\n[HALTED] Program complete.  CPU halted.\r\n"

    .section .text
    .globl  exit
    .type   exit, @function

exit:
    /* ── 1. Disable global interrupts ───────────────────────────────────── */
    /* Clear mstatus.MIE (bit 3) — no interrupt handler will fire after this. */
    csrci   mstatus, 8

    /* ── 2. Print halt message over UART ────────────────────────────────── */
    la      a0, .Lstr_halted
    call    uart_puts

    /* ── 3. Idle forever with WFI ───────────────────────────────────────── */
    /* WFI idles the core.  In Renode this consumes minimal simulation time  */
    /* compared to a spin loop.  Because MIE is cleared, no interrupt can    */
    /* wake the CPU — it stays here until Renode is quit.                    */
.Lhalt:
    wfi
    j       .Lhalt

    .size   exit, . - exit
