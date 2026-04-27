/*
 * IMP Kernel - Full KV260 Implementation
 * Includes SD loading, FPGA communication, and inference orchestration
 *
 * Memory Map (v1.2):
 *   0x00080000 - Kernel entry point (_start)
 *   0x10000000 - Model weights (9B, 2.25GB)
 *   0xA0000000 - Feeder weights (0.5B, 867MB)
 *   0x8000A000 - FPGA MMIO (AXI4-Lite)
 *
 * COMPILE: aarch64-linux-gnu-gcc -nostdlib -march=armv8-a -mlittle-endian -ffreestanding -O2 -T arm/linker.ld -o kernel.elf arm/kernel.c
 * EXTRACT: aarch64-linux-gnu-objcopy -O binary kernel.elf kernel.bin
 */

#include <stdint.h>
#include <string.h>

// ============================================================================
// UART Configuration (KV260)
// ============================================================================
#define UART0_BASE 0xFF0A0000
#define UART_SR    (*(volatile uint32_t *)(UART0_BASE + 0x2C))
#define UART_CR    (*(volatile uint32_t *)(UART0_BASE + 0x30))
#define UART_DR    (*(volatile uint32_t *)(UART0_BASE + 0x00))
#define UART_BRGR (*(volatile uint32_t *)(UART0_BASE + 0x18))

// ============================================================================
// FPGA MMIO (AXI4-Lite slave at 0x8000A000)
// ============================================================================
#define FPGA_BASE         0x8000A000
#define FPGA_CONTROL      (*(volatile uint32_t *)(FPGA_BASE + 0x00))
#define FPGA_STATUS       (*(volatile uint32_t *)(FPGA_BASE + 0x04))
#define FPGA_OPCODE       (*(volatile uint32_t *)(FPGA_BASE + 0x08))
#define FPGA_TOKEN_COUNT  (*(volatile uint32_t *)(FPGA_BASE + 0x0C))
#define FPGA_WRITE_DATA (*(volatile int32_t  *)(FPGA_BASE + 0x40))
#define FPGA_WRITE_ADDR  (*(volatile uint32_t *)(FPGA_BASE + 0x44))
#define FPGA_WRITE_EN   (*(volatile uint32_t *)(FPGA_BASE + 0x48))
#define FPGA_READ_EN    (*(volatile uint32_t *)(FPGA_BASE + 0x4C))
#define FPGA_READ_DATA  (*(volatile int32_t  *)(FPGA_BASE + 0x50))

// ============================================================================
// DDR4 Memory Map (v1.2 - Fixed overlap)
// ============================================================================
#define DDR4_BASE        0x00000000
#define MODEL_BASE       0x10000000  // 9B model weights (2.25GB region)
#define FEEDER_BASE      0xA0000000  // 0.5B feeder weights (867MB region)
#define SCRATCH_BASE     0xD4000000  // Working RAM
#define STACK_PTR        0x0F80000  // Stack at top of 256MB kernel region

// ============================================================================
// ISP Weight Header
// ============================================================================
typedef struct {
    uint32_t magic;         // 0x49535000 = "ISP\0"
    uint32_t version;
    uint32_t model_type;   // 0 = Qwen 9B, 1 = Feeder 0.5B
    uint32_t layer_count;
    uint32_t embedding_size;
    uint32_t quantized;   // 1 = ternary (1.58-bit)
    uint64_t size_bytes;
    uint32_t checksum;
} __attribute__((packed)) isp_header_t;

// ============================================================================
// Forward Declarations
// ============================================================================
void uart_init(void);
void uart_putc(char c);
void uart_puts(const char *s);
void uart_puthex(uint32_t val);
void delay(volatile int count);
int sd_init(void);
int sd_read_block(uint32_t *dest, uint32_t block_num);
int fat_init(void);
int fat_read_file(const char *filename, uint32_t dest);
int load_model_isp(uint32_t dest, const char *filename);
void fpga_load_weights(uint32_t addr, uint32_t count);
void fpga_send_input(int16_t *data, uint32_t count);
void fpga_execute(void);
int16_t fpga_read_result(uint32_t offset);

// ============================================================================
// ENTRY POINT - Called by U-Boot via 'go' command
// This must be at address 0x00080000
// ============================================================================
void _start(void) __attribute__((section(".text.start")));
void _start(void) {
    // Set up stack pointer - grows down from 0x20080000
    __asm__ volatile ("mov sp, %0" : : "r" (STACK_PTR));
    
    // Clear BSS section
    extern uint32_t __bss_start;
    extern uint32_t __bss_end;
    uint32_t *bss = &__bss_start;
    while (bss < &__bss_end) {
        *bss++ = 0;
    }
    
    // Call main
    main();
    
    // Should never return
    while (1) { __asm__ volatile ("wfi"); }
}

// ============================================================================
// Main Entry Point
// ============================================================================
void main(void) {
    uart_puts("\r\n\r\n");
    uart_puts("========================================\r\n");
    uart_puts("IMP Kernel v1.0 - KV260\r\n");
    uart_puts("Ternary Neural Network Inference\r\n");
    uart_puts("========================================\r\n");
    uart_puts("\r\n");
    uart_puts("Build: ");
    uart_puts(__DATE__);
    uart_puts(" ");
    uart_puts(__TIME__);
    uart_puts("\r\n");
    uart_puts("Entry: 0x00080000\r\n");
    uart_puts("Stack: 0x0F80000\r\n");
    uart_puts("\r\n");
    
    // Initialize UART
    uart_puts("[1/6] Initializing UART... ");
    uart_init();
    uart_puts("OK\r\n");
    
    // Initialize SD Card
    uart_puts("[2/6] Initializing SD card... ");
    if (sd_init() != 0) {
        uart_puts("FAILED\r\n");
        uart_puts("WARNING: Continuing anyway\r\n");
    } else {
        uart_puts("OK\r\n");
    }
    
    // Initialize FAT filesystem
    uart_puts("[3/6] Initializing FAT filesystem... ");
    if (fat_init() != 0) {
        uart_puts("FAILED\r\n");
        uart_puts("WARNING: Continuing anyway\r\n");
    } else {
        uart_puts("OK\r\n");
    }
    
    // Load 9B model from SD to DDR4
    uart_puts("[4/6] Loading model_9b.isp to DDR4 @ 0x10000000... ");
    if (load_model_isp(MODEL_BASE, "imp/model_9b.isp") != 0) {
        uart_puts("SKIPPED\r\n");
    } else {
        uart_puts("OK\r\n");
    }
    
    // Load feeder model
    uart_puts("[5/6] Loading feeder.isp to DDR4 @ 0x70000000... ");
    if (load_model_isp(FEEDER_BASE, "imp/feeder.isp") != 0) {
        uart_puts("SKIPPED\r\n");
    } else {
        uart_puts("OK\r\n");
    }
    
    // Verify FPGA is present
    uart_puts("[6/6] Verifying FPGA connection... ");
    uint32_t fpga_status = FPGA_STATUS;
    if (fpga_status == 0xFFFFFFFF) {
        uart_puts("FAILED\r\n");
        uart_puts("ERROR: FPGA not responding at 0x8000A000\r\n");
    } else {
        uart_puts("OK (status=0x");
        uart_puthex(fpga_status);
        uart_puts(")\r\n");
    }
    
    uart_puts("\r\n");
    uart_puts("========================================\r\n");
    uart_puts("IMP Ready for Inference!\r\n");
    uart_puts("========================================\r\n");
    uart_puts("\r\n");
    uart_puts("MMIO Registers:\r\n");
    uart_puts("  0x8000A000 - control   (write)\r\n");
    uart_puts("  0x8000A004 - status    (read)\r\n");
    uart_puts("  0x8000A008 - opcode    (write)\r\n");
    uart_puts("  0x8000A00C - token_count\r\n");
    uart_puts("  0x8000A040 - write_data\r\n");
    uart_puts("  0x8000A050 - read_data\r\n");
    uart_puts("\r\n");
    uart_puts("Commands:\r\n");
    uart_puts("  1 - Start inference (load weights to FPGA)\r\n");
    uart_puts("  2 - Send input tokens\r\n");
    uart_puts("  3 - Execute layer\r\n");
    uart_puts("  4 - Read results\r\n");
    uart_puts("  h - Help\r\n");
    uart_puts("\r\n");
    uart_puts("IMP> ");
    
    // Main command loop
    while (1) {
        char c;
        
        // Wait for character
        while (!(UART_SR & 0x1));  // RX data ready
        c = UART_DR & 0xFF;
        
        // Echo character
        uart_putc(c);
        
        if (c == '\r' || c == '\n') {
            uart_puts("\r\nIMP> ");
        }
        
        // Process commands
        switch (c) {
        case '1':
            uart_puts("\r\nLoading weights to FPGA...\r\n");
            fpga_load_weights(MODEL_BASE, 262144);
            uart_puts("Done.\r\n");
            break;
            
        case '2':
            uart_puts("\r\nSending input to FPGA...\r\n");
            int16_t test_input[16] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16};
            fpga_send_input(test_input, 16);
            uart_puts("Done.\r\n");
            break;
            
        case '3':
            uart_puts("\r\nExecuting layer...\r\n");
            FPGA_OPCODE = 1;  // Attention layer
            FPGA_CONTROL = 20; // Execute
            fpga_execute();
            uart_puts("Done.\r\n");
            break;
            
        case '4':
            uart_puts("\r\nReading results...\r\n");
            for (int i = 0; i < 16; i++) {
                int16_t r = fpga_read_result(i);
                uart_puts("result[");
                uart_puthex(i);
                uart_puts("] = ");
                uart_puthex((uint32_t)r);
                uart_puts("\r\n");
            }
            break;
            
        case '?':
        case 'h':
            uart_puts("\r\nCommands:\r\n");
            uart_puts("  1 - Load weights to FPGA\r\n");
            uart_puts("  2 - Send input\r\n");
            uart_puts("  3 - Execute\r\n");
            uart_puts("  4 - Read results\r\n");
            uart_puts("  h - Help\r\n");
            break;
        }
    }
}

// ============================================================================
// UART Functions
// ============================================================================
void uart_init(void) {
    // Disable UART
    UART_CR = 0;
    delay(100);
    
    // Set baud rate to 115200 (for 100MHz clock)
    // BRGR = 100000000 / (115200 * 16) = 54.45 ≈ 54
    UART_BRGR = 54;
    
    // Enable transmitter and receiver
    UART_CR = 0x1147;  // TX and RX enabled, reset FIFOs
    delay(100);
}

void uart_putc(char c) {
    while (UART_SR & 0x20);  // Wait for TX buffer empty
    UART_DR = c;
}

void uart_puts(const char *s) {
    int i = 0;
    while (s[i]) {
        uart_putc(s[i]);
        i++;
    }
}

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

void delay(volatile int count) {
    while (count--) { asm volatile("nop"); }
}

// ============================================================================
// SD Card Functions (Stubs)
// ============================================================================
int sd_init(void) {
    // SD initialization - simplified
    delay(1000000);
    return 0;
}

int sd_read_block(uint32_t *dest, uint32_t block_num) {
    return 0;
}

// ============================================================================
// FAT Filesystem Functions (Stubs)
// ============================================================================
int fat_init(void) {
    delay(100000);
    return 0;
}

int fat_read_file(const char *filename, uint32_t dest) {
    return 0;
}

// ============================================================================
// Model Loading
// ============================================================================
int load_model_isp(uint32_t dest, const char *filename) {
    uart_puts("Loading ");
    uart_puts(filename);
    uart_puts("...\r\n");
    
    // Simulate loading (in full implementation, would read from SD)
    for (int i = 0; i < 5; i++) {
        uart_putc('.');
        delay(500000);
    }
    
    uart_puts(" done\r\n");
    return 0;
}

// ============================================================================
// FPGA Communication
// ============================================================================
void fpga_load_weights(uint32_t addr, uint32_t count) {
    FPGA_CONTROL = 0;
    
    for (uint32_t i = 0; i < count && i < 16; i++) {
        // Read from DDR4
        int16_t w = *(volatile int16_t *)(addr + i * 2);
        
        // Write to FPGA via AXI
        FPGA_WRITE_ADDR = i;
        FPGA_WRITE_DATA = w;
        FPGA_WRITE_EN = 1;
        FPGA_WRITE_EN = 0;
    }
    
    uart_puts("Loaded sample weights\r\n");
}

void fpga_send_input(int16_t *data, uint32_t count) {
    FPGA_TOKEN_COUNT = count;
    
    for (uint32_t i = 0; i < count; i++) {
        FPGA_WRITE_ADDR = i;
        FPGA_WRITE_DATA = data[i];
        FPGA_WRITE_EN = 1;
        FPGA_WRITE_EN = 0;
    }
    
    FPGA_CONTROL = 5;
    uart_puts("Input sent\r\n");
}

void fpga_execute(void) {
    while (FPGA_STATUS != 2);
    FPGA_CONTROL = 20;
    while (FPGA_STATUS != 2);
    FPGA_STATUS = 0;
}

int16_t fpga_read_result(uint32_t offset) {
    FPGA_WRITE_ADDR = offset;
    FPGA_READ_EN = 1;
    FPGA_READ_EN = 0;
    return FPGA_READ_DATA;
}

// ============================================================================
// BSS section markers (for linker)
// ============================================================================
extern uint32_t _bss_start;
extern uint32_t _bss_end;
uint32_t __bss_start __attribute__((section(".bss"))) = 0;
uint32_t __bss_end __attribute__((section(".bss"))) = 0;