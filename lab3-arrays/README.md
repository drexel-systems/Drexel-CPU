# Lab 3 — Array Processing

Practice indexed memory access, loops, and the RISC-V calling convention by implementing four classic array operations in assembly.

## What It Does

`main` calls four functions on a hard-coded 10-element array `{42, 17, 89, 5, 63, 28, 71, 14, 96, 33}` and prints results over UART:

```
=== CS281 Lab 3: Array Processing ===

Array: 42 17 89 5 63 28 71 14 96 33

--- Part 1: Sum ---
Sum = 458

--- Part 2: Min / Max ---
Min = 5
Max = 96

--- Part 3: Reverse ---
Reversed: 33 96 14 71 28 63 5 89 17 42

Done.
```

Until you fill in the TODOs, each function returns 0 (or does nothing).

## Learning Objectives

**Indexed memory access** — Arrays in memory are contiguous words; element `i` is at address `base + i*4`. To reach `array[i]` when `i` is in a register, shift left by 2 (`slli t2, i, 2`) then add to the base pointer. This is the assembly equivalent of `array[i]` in C.

**Loop structure** — Every array operation follows the same skeleton: initialize a counter or pointer, test the exit condition at the top of the loop with a branch, do the body, update the counter, and jump back. Recognizing this pattern makes both writing and reading assembly loops much easier.

**Register calling convention** — `a0`/`a1` carry arguments in, `a0` carries the return value out. Temporary registers `t0`–`t6` are yours to use freely, but `s0`–`s11` must be saved and restored if you use them (callee-saved). When `main` calls `array_sum`, for example, it passes the array pointer in `a0` and the count in `a1`, then reads the sum back from `a0` after `ret`.

**Two-pointer technique** — `array_reverse` requires simultaneous access to both ends of the array. One pointer starts at `array[0]` and walks forward; another starts at `array[n-1]` and walks backward. Swap the elements they point to, advance both, stop when they meet or cross.

**Stack discipline** — `array_reverse` cannot work in-place on the `.rodata` array (the linker places `.rodata` in ROM). `main` copies the array onto the stack first using `array_copy`, which is provided. Students see how `addi sp, sp, -N` / `addi sp, sp, N` allocates and frees stack space around a temporary buffer.

## Your Task

Four functions in `main.S` have `TODO` stubs — replace the placeholder `ret` (or `li a0, 0`) with a working implementation:

| Function | Signature | What to do |
|----------|-----------|------------|
| `array_sum` | `(int *arr, int n) → int` | Sum all elements; return total in `a0` |
| `array_min` | `(int *arr, int n) → int` | Return the smallest element |
| `array_max` | `(int *arr, int n) → int` | Return the largest element |
| `array_reverse` | `(int *arr, int n)` | Reverse the array in-place; no return value |

`array_copy` and `print_array` are fully implemented — read them to understand how loops and function calls work before writing your own.

## Key Files

| File | Role |
|------|------|
| `main.S` | Array data, `main`, and the four TODO functions |
| `../hardware/lib/uart.S` | `uart_putchar`, `uart_puts` — used by `print_array` |
| `../hardware/lib/startup.S` | Boot sequence (same as Lab 1) |
| `../hardware/lib/cs281.inc` | Register map (not used directly in this lab) |

## Running It

```bash
make run          # build and launch Renode
make uart-connect # (second terminal) see the array output
```

## Useful Instructions

```asm
la   t0, array        # load address of array into t0
lw   t1, 0(t0)        # t1 = array[0]
lw   t1, 4(t0)        # t1 = array[1]

# Index by variable i (in t2):
slli t3, t2, 2        # t3 = i * 4
add  t3, t0, t3       # t3 = &array[i]
lw   t4, 0(t3)        # t4 = array[i]

blt  t1, t2, .Llabel  # branch if t1 < t2 (signed)
bgt  t1, t2, .Llabel  # branch if t1 > t2 (signed)
```

## Extensions

Once the four functions work, try:
- Print the index (not just the value) of the min and max elements.
- Implement bubble sort — call it and print the sorted array.
- Compute the integer average (you will need `div` or repeated subtraction).
- Count how many elements exceed a threshold read from DIP\_SW0.
