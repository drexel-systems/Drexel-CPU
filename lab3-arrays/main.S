/* =============================================================================
 * CS281 Lab 3 — Array Processing
 * File: lab3-arrays/main.S
 *
 * Objective
 *   Practice indexed memory access and loops by implementing four classic
 *   array operations on a hard-coded integer array:
 *
 *     1. array_sum    — sum all elements, return total in a0
 *     2. array_min    — find minimum element, return value in a0
 *     3. array_max    — find maximum element, return value in a0
 *     4. array_reverse — reverse the array in-place
 *
 *   Each function is called from main and its result is printed over UART.
 *
 * Expected UART output (telnet localhost 3456 / make uart-connect)
 *   === CS281 Lab 3: Array Processing ===
 *
 *   Array: 42 17 89 5 63 28 71 14 96 33
 *
 *   --- Part 1: Sum ---
 *   Sum = ???        <-- you fill this in
 *
 *   --- Part 2: Min / Max ---
 *   Min = ???        <-- you fill this in
 *   Max = ???        <-- you fill this in
 *
 *   --- Part 3: Reverse ---
 *   Reversed: ???    <-- you fill this in
 *
 *   Done.
 *
 * Register conventions (RISC-V calling convention)
 *   a0-a7   argument / return value registers (caller-saved)
 *   t0-t6   temporaries (caller-saved — you can clobber freely)
 *   s0-s11  saved registers (callee-saved — must push/pop if you use them)
 *   ra      return address (save with addi sp,-4/sw ra,0(sp) if calling subroutines)
 *
 * Memory access reminder
 *   la   t0, array        # t0 = address of array[0]
 *   lw   t1, 0(t0)        # t1 = array[0]
 *   lw   t1, 4(t0)        # t1 = array[1]   (each int is 4 bytes)
 *   lw   t1, 0(t0)        # load word at address in t0
 *   sw   t1, 0(t0)        # store word
 *
 *   To index by a variable i:
 *     slli t2, t2, 2      # t2 = i * 4   (shift left 2 = multiply by 4)
 *     add  t3, t0, t2     # t3 = &array[i]
 *     lw   t4, 0(t3)      # t4 = array[i]
 *
 * Extensions to try
 *   - Print the array index of the min and max elements
 *   - Implement bubble sort
 *   - Compute the average (integer division)
 *   - Count elements above / below a threshold read from BTN0
 * =============================================================================*/

    .include "../hardware/lib/cs281.inc"

/* ── Array size ───────────────────────────────────────────────────────────── */
.equ ARRAY_SIZE, 10

/* ── Read-Only Data ───────────────────────────────────────────────────────── */
    .section .rodata

str_banner:   .string "=== CS281 Lab 3: Array Processing ===\r\n\r\n"
str_array_hdr:.string "Array: "
str_newline:  .string "\r\n"
str_space:    .string " "

str_sum_hdr:  .string "\r\n--- Part 1: Sum ---\r\nSum = "
str_min_hdr:  .string "\r\n--- Part 2: Min / Max ---\r\nMin = "
str_max_lbl:  .string "\r\nMax = "
str_rev_hdr:  .string "\r\n--- Part 3: Reverse ---\r\nReversed: "
str_done:     .string "\r\nDone.\r\n"

/* Hard-coded array of 10 integers */
    .section .rodata
    .align 2
array:
    .word  42, 17, 89,  5, 63
    .word  28, 71, 14, 96, 33
array_end:

/* ── Code ─────────────────────────────────────────────────────────────────── */
    .section .text
    .globl  main
    .type   main, @function

main:
    /* Save ra — we call subroutines */
    addi    sp, sp, -4
    sw      ra, 0(sp)

    /* ── Banner ───────────────────────────────────────────────────────────── */
    la      a0, str_banner
    call    uart_puts

    /* ── Print original array ─────────────────────────────────────────────── */
    la      a0, str_array_hdr
    call    uart_puts
    la      a0, array
    li      a1, ARRAY_SIZE
    call    print_array

    /* ── Part 1: Sum ──────────────────────────────────────────────────────── */
    la      a0, str_sum_hdr
    call    uart_puts

    la      a0, array
    li      a1, ARRAY_SIZE
    call    array_sum           /* result in a0 */

    call    uart_put_uint       /* print result */

    la      a0, str_newline
    call    uart_puts

    /* ── Part 2: Min ──────────────────────────────────────────────────────── */
    la      a0, str_min_hdr
    call    uart_puts

    la      a0, array
    li      a1, ARRAY_SIZE
    call    array_min           /* result in a0 */

    call    uart_put_uint

    /* ── Part 2: Max ──────────────────────────────────────────────────────── */
    la      a0, str_max_lbl
    call    uart_puts

    la      a0, array
    li      a1, ARRAY_SIZE
    call    array_max           /* result in a0 */

    call    uart_put_uint

    la      a0, str_newline
    call    uart_puts

    /* ── Part 3: Reverse ──────────────────────────────────────────────────── */
    la      a0, str_rev_hdr
    call    uart_puts

    /* Note: array is in .rodata so we cannot reverse it in-place.
     * Copy it to a stack buffer first, then reverse. */
    addi    sp, sp, -44             /* 10 words * 4 bytes = 40 + 4 alignment */
    mv      a0, sp
    la      a1, array
    li      a2, ARRAY_SIZE
    call    array_copy              /* copy array → stack buffer */

    mv      a0, sp
    li      a1, ARRAY_SIZE
    call    array_reverse           /* reverse stack buffer in-place */

    mv      a0, sp
    li      a1, ARRAY_SIZE
    call    print_array

    addi    sp, sp, 44

    /* ── Done ─────────────────────────────────────────────────────────────── */
    la      a0, str_done
    call    uart_puts

    /* Restore ra and return */
    lw      ra, 0(sp)
    addi    sp, sp, 4
    ret

    .size   main, . - main


/* =============================================================================
 * array_sum — sum all elements of an integer array
 *
 * Arguments
 *   a0  — pointer to array (int*)
 *   a1  — number of elements
 *
 * Returns
 *   a0  — sum of all elements
 *
 * TODO: Implement this function.
 *
 * Hint: use a loop counter in t1 and accumulate into t2.
 *   Initialize sum to 0.
 *   For each element: load it, add to sum, advance pointer, decrement counter.
 * =============================================================================*/
    .globl  array_sum
    .type   array_sum, @function
array_sum:
    /* TODO: implement array sum */
    li      a0, 0               /* placeholder — remove and replace */
    ret
    .size   array_sum, . - array_sum


/* =============================================================================
 * array_min — find the minimum element in an integer array
 *
 * Arguments
 *   a0  — pointer to array (int*)
 *   a1  — number of elements
 *
 * Returns
 *   a0  — minimum element value
 *
 * TODO: Implement this function.
 *
 * Hint: Initialize your "current min" to array[0], then loop from index 1.
 *   Use blt (branch if less than) to compare and conditionally update.
 * =============================================================================*/
    .globl  array_min
    .type   array_min, @function
array_min:
    /* TODO: implement array min */
    li      a0, 0               /* placeholder — remove and replace */
    ret
    .size   array_min, . - array_min


/* =============================================================================
 * array_max — find the maximum element in an integer array
 *
 * Arguments
 *   a0  — pointer to array (int*)
 *   a1  — number of elements
 *
 * Returns
 *   a0  — maximum element value
 *
 * TODO: Implement this function.
 *
 * Hint: Same structure as array_min, but use bgt (branch if greater than).
 * =============================================================================*/
    .globl  array_max
    .type   array_max, @function
array_max:
    /* TODO: implement array max */
    li      a0, 0               /* placeholder — remove and replace */
    ret
    .size   array_max, . - array_max


/* =============================================================================
 * array_reverse — reverse an integer array in-place
 *
 * Arguments
 *   a0  — pointer to array (int*)
 *   a1  — number of elements
 *
 * Returns
 *   nothing (modifies array in place)
 *
 * TODO: Implement this function.
 *
 * Hint: Use two pointers — one starting at array[0], one at array[n-1].
 *   Swap the values at both pointers, advance left pointer forward,
 *   advance right pointer backward, and stop when they meet or cross.
 *
 *   Swap pattern (no temp register needed if you use XOR, but a temp is clearer):
 *     lw  t2, 0(t0)   # t2 = *left
 *     lw  t3, 0(t1)   # t3 = *right
 *     sw  t3, 0(t0)   # *left  = t3
 *     sw  t2, 0(t1)   # *right = t2
 * =============================================================================*/
    .globl  array_reverse
    .type   array_reverse, @function
array_reverse:
    /* TODO: implement array reverse */
    ret
    .size   array_reverse, . - array_reverse


/* =============================================================================
 * array_copy — copy n words from src to dst
 *
 * Arguments
 *   a0  — dst pointer (int*)
 *   a1  — src pointer (int*)
 *   a2  — number of elements
 *
 * Provided for you — used by main to copy .rodata array onto stack.
 * =============================================================================*/
    .globl  array_copy
    .type   array_copy, @function
array_copy:
    beqz    a2, .Lcopy_done
.Lcopy_loop:
    lw      t0, 0(a1)
    sw      t0, 0(a0)
    addi    a0, a0, 4
    addi    a1, a1, 4
    addi    a2, a2, -1
    bnez    a2, .Lcopy_loop
.Lcopy_done:
    ret
    .size   array_copy, . - array_copy


/* =============================================================================
 * print_array — print n space-separated integers over UART
 *
 * Arguments
 *   a0  — pointer to array (int*)
 *   a1  — number of elements
 *
 * Provided for you.
 * =============================================================================*/
    .globl  print_array
    .type   print_array, @function
print_array:
    addi    sp, sp, -16
    sw      ra, 12(sp)
    sw      s0,  8(sp)
    sw      s1,  4(sp)
    sw      s2,  0(sp)

    mv      s0, a0          /* s0 = array pointer */
    mv      s1, a1          /* s1 = count */
    li      s2, 0           /* s2 = index */

.Lprint_loop:
    bge     s2, s1, .Lprint_done

    /* load and print element */
    slli    t0, s2, 2
    add     t0, s0, t0
    lw      a0, 0(t0)
    call    uart_put_uint

    /* print space (but not after last element) */
    addi    t1, s1, -1
    bge     s2, t1, .Lprint_no_space
    la      a0, str_space
    call    uart_puts
.Lprint_no_space:

    addi    s2, s2, 1
    j       .Lprint_loop

.Lprint_done:
    la      a0, str_newline
    call    uart_puts

    lw      s2,  0(sp)
    lw      s1,  4(sp)
    lw      s0,  8(sp)
    lw      ra, 12(sp)
    addi    sp, sp, 16
    ret
    .size   print_array, . - print_array


/* =============================================================================
 * uart_put_uint — print an unsigned 32-bit integer in decimal over UART
 *
 * Arguments
 *   a0  — value to print
 *
 * Provided for you.
 * =============================================================================*/
    .globl  uart_put_uint
    .type   uart_put_uint, @function
uart_put_uint:
    addi    sp, sp, -20
    sw      ra,  16(sp)
    sw      s0,  12(sp)
    sw      s1,   8(sp)     /* s1 = digit pointer (callee-saved, survives call) */

    /* Special case: 0 */
    bnez    a0, .Lnot_zero
    li      a0, '0'
    call    uart_putchar
    j       .Lput_done

.Lnot_zero:
    /* Build digits in the 8-byte scratch area at sp+0..sp+7 (below saved regs).
     * s1 walks downward from sp+8 as we push digits; then walks upward to print.
     * Using s1 (callee-saved) so call uart_putchar cannot clobber the pointer. */
    mv      s0, a0          /* s0 = remaining value */
    addi    s1, sp, 8       /* s1 = top of digit scratch area */
    li      t0, 10

.Ldigit_loop:
    beqz    s0, .Lprint_digits
    remu    t1, s0, t0      /* t1 = s0 % 10 */
    addi    t1, t1, '0'
    addi    s1, s1, -1
    sb      t1, 0(s1)
    divu    s0, s0, t0      /* s0 = s0 / 10 */
    j       .Ldigit_loop

.Lprint_digits:
    /* s1 points at first (most-significant) digit; sp+8 is one past last */
    addi    t0, sp, 8
    bge     s1, t0, .Lput_done
    lb      a0, 0(s1)
    call    uart_putchar    /* s1 is callee-saved — still valid after call */
    addi    s1, s1, 1
    j       .Lprint_digits

.Lput_done:
    lw      s1,   8(sp)
    lw      s0,  12(sp)
    lw      ra,  16(sp)
    addi    sp, sp, 20
    ret
    .size   uart_put_uint, . - uart_put_uint
