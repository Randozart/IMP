/*
 * IMP Kernel Startup - ARM64 Cortex-A53
 * Sets up stack and branches to main()
 */

.section .text.start
.global _start
.type _start, @function

_start:
    /* Set up stack - grows down from 0x00100000 */
    mov sp, #0x00100000
    
    /* Clear .bss section */
    adr x0, __bss_start
    adr x1, __bss_end
    mov x2, #0
    
clear_bss:
    cmp x0, x1
    b.eq run_main
    str x2, [x0], #8
    b clear_bss

run_main:
    /* Call main() */
    bl main
    
    /* If main returns, loop forever */
stop:
    b stop

.size _start, .-_start

/*
 * Exception vectors - minimal for bare-metal
 */
.section .vector_table
.global vector_table
type vector_table, @object

vector_table:
    b _start      /* Reset */
    b stop        /* Undefined */
    b stop        /* Supervisor Call */
    b stop        /* Prefetch Abort */
    b stop        /* Data Abort */
    b stop        /* Reserved */
    b stop        /* IRQ */
    b stop        /* FIQ */