/*
 * IMP Kernel - Minimal C stub for testing
 * Tests UART, then loads and runs inference
 */

#include <stdint.h>

// UART0 configuration (KV260)
#define UART0_BASE 0xFF0A0000
#define UART_SR (*(volatile uint32_t *)(UART0_BASE + 0x2C))  // Status
#define UART_CR (*(volatile uint32_t *)(UART0_BASE + 0x30))  // Control
#define UART_DR (*(volatile uint32_t *)(UART0_BASE + 0x00))  // Data

// FPGA MMIO (AXI4-Lite slave)
#define FPGA_BASE 0x8000A000
#define FPGA_CONTROL (*(volatile uint32_t *)(FPGA_BASE + 0x00))
#define FPGA_STATUS (*(volatile uint32_t *)(FPGA_BASE + 0x04))
#define FPGA_OPCODE (*(volatile uint32_t *)(FPGA_BASE + 0x08))
#define FPGA_TOKEN_COUNT (*(volatile uint32_t *)(FPGA_BASE + 0x0C))
#define FPGA_WRITE_DATA (*(volatile int32_t *)(FPGA_BASE + 0x40))
#define FPGA_WRITE_ADDR (*(volatile uint32_t *)(FPGA_BASE + 0x44))
#define FPGA_WRITE_EN (*(volatile uint32_t *)(FPGA_BASE + 0x48))
#define FPGA_READ_EN (*(volatile uint32_t *)(FPGA_BASE + 0x4C))
#define FPGA_READ_DATA (*(volatile int32_t *)(FPGA_BASE + 0x50))

// Simple strlen
int strlen(const char *s) {
    int len = 0;
    while (s[len]) len++;
    return len;
}

// UART put character
void uart_putc(char c) {
    while (UART_SR & 0x20);  // Wait for TX buffer empty
    UART_DR = c;
}

// UART put string
void uart_puts(const char *s) {
    int i = 0;
    while (s[i]) {
        uart_putc(s[i]);
        i++;
    }
}

// Print hex value
void uart_puthex(uint32_t val) {
    char hex[] = "0123456789ABCDEF";
    char buf[9];
    int i = 0;
    for (int j = 7; j >= 0; j--) {
        buf[i++] = hex[(val >> (j * 4)) & 0xF];
    }
    buf[8] = 0;
    uart_puts(buf);
}

// Delay function
void delay(volatile int count) {
    while (count--) { asm volatile("nop"); }
}

void main(void) {
    uart_puts("\r\nIMP Kernel v0.3\r\n");
    uart_puts("=====================\r\n");
    
    // Check FPGA is present
    uart_puts("Checking FPGA...\r\n");
    uint32_t status = FPGA_STATUS;
    uart_puts("FPGA Status: 0x");
    uart_puthex(status);
    uart_puts("\r\n");
    
    if (status == 0) {
        uart_puts("ERROR: FPGA not responding!\r\n");
        while (1) { delay(1000000); }
    }
    
    // Write to FPGA control register
    uart_puts("Writing to FPGA MMIO...\r\n");
    FPGA_CONTROL = 0x0;  // Reset/set idle
    delay(100000);
    
    FPGA_WRITE_DATA = 0x12345678;
    FPGA_WRITE_ADDR = 0;
    FPGA_WRITE_EN = 1;
    FPGA_WRITE_EN = 0;
    
    uart_puts("Written: 0x12345678 to addr 0\r\n");
    
    // Read back
    FPGA_READ_EN = 1;
    FPGA_READ_EN = 0;
    int32_t read_val = FPGA_READ_DATA;
    
    uart_puts("Read back: 0x");
    uart_puthex(read_val);
    uart_puts("\r\n");
    
    if (read_val == 0x12345678) {
        uart_puts("SUCCESS: FPGA read/write working!\r\n");
    } else {
        uart_puts("WARNING: FPGA returned different value\r\n");
    }
    
    // Test control register
    uart_puts("Testing control register...\r\n");
    FPGA_CONTROL = 1;  // Trigger load
    delay(100000);
    uart_puts("Control set to 1\r\n");
    
    FPGA_OPCODE = 5;  // Example opcode
    uart_puts("Opcode set to 5\r\n");
    
    FPGA_TOKEN_COUNT = 64;
    uart_puts("Token count set to 64\r\n");
    
    uart_puts("\r\nIMP Kernel ready!\r\n");
    uart_puts("Waiting for inference requests...\r\n");
    uart_puts("\r\n> ");
    
    // Main loop - echo characters
    while (1) {
        // Wait for character
        while (!(UART_SR & 0x1));  // RX data ready
        
        char c = UART_DR & 0xFF;
        
        if (c) {
            uart_putc(c);
            
            // Echo back
            if (c == '\r') {
                uart_puts("\r\n> ");
            }
        }
    }
}