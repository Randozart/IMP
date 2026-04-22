// IMP Bare-Metal Kernel - ARM state machine for KV260 LLM inference orchestration
//     Copyright (C) 2026 Randy Smits-Schreuder Goedheijt
//
// IMP Bare-Metal Kernel - ARM Cortex-A53
// Target: KV260, runs without Linux
// Compile with: rustc --target arm-none-eabi --edition 2021
//
// NOTE: This is no_std code - no heap allocation!
// Use heapless::Vec for fixed-size collections, not Vec
// Use core::fmt::write! instead of format! macro

#![no_std]
#![no_main]
#![feature(const_mut_refs)]

// Note: heapless crate would be needed for Vec-like fixed collections
// For now, we use plain arrays

use core::fmt::Write;
use core::sync::atomic::{AtomicBool, Ordering};

// =============================================================================
// MMIO Hardware Interface
// =============================================================================

// Hardware memory-mapped registers at 0x4000A000 (FPGA AXI4-Lite slave)
const MMIO_BASE: *mut State = 0x4000A000 as *mut State;

#[repr(C)]
pub struct State {
    pub control: u32,        // 0x4000A000 - Command to FPGA (mailbox)
    pub status: u32,          // 0x4000A004 - FPGA status
    pub opcode: u32,         // 0x4000A008 - Operation code
    pub token_count: u32,    // 0x4000A00C - Token counter
    _pad0: [u32; 12],        // Padding to 0x4000A040
    pub write_data: i32,     // 0x4000A040 - Mailbox: data to write (triggers load_weights/load_input)
    pub write_addr: u32,      // 0x4000A044 - Mailbox: address/index for writes
    pub write_en: u32,       // 0x4000A048 - Mailbox: write enable pulse
    pub read_en: u32,        // 0x4000A04C - Mailbox: read enable pulse
    pub read_data: i32,      // 0x4000A050 - Mailbox: data read back from scratch
}

impl State {
    pub unsafe fn get() -> &'static mut State {
        &mut *MMIO_BASE
    }

    pub fn wait_ready(&self) {
        while self.status != 2 {
            core::hint::spin_loop();
        }
    }

    pub fn send_layer(&mut self, layer_type: u32) {
        self.opcode = layer_type;
        self.control = 20;
    }
}

#[derive(Debug, Clone, Copy)]
pub enum LayerType {
    Attention = 1,
    MlpGate = 2,
    MlpUp = 3,
    MlpDown = 4,
}

// =============================================================================
// UART Driver
// =============================================================================

const UART_BASE: *mut u32 = 0xFF0A0000 as *mut u32;

pub fn uart_putc(c: u8) {
    unsafe {
        core::ptr::write_volatile(UART_BASE, c as u32);
    }
}

pub fn uart_puts(s: &str) {
    for c in s.bytes() {
        uart_putc(c);
    }
}

// Fixed-size buffer for uart output (no heap)
pub struct UartBuffer {
    data: [u8; 128],
    len: usize,
}

impl UartBuffer {
    pub fn new() -> Self {
        UartBuffer {
            data: [0u8; 128],
            len: 0,
        }
    }

    pub fn write_str(&mut self, s: &str) {
        for c in s.bytes() {
            if self.len < 128 {
                self.data[self.len] = c;
                self.len += 1;
            }
        }
    }

    pub fn flush(&mut self) {
        for i in 0..self.len {
            uart_putc(self.data[i]);
        }
        self.len = 0;
    }
}

impl core::fmt::Write for UartBuffer {
    fn write_str(&mut self, s: &str) -> core::fmt::Result {
        self.write_str(s);
        Ok(())
    }
}

// =============================================================================
// Ethernet (TCP - stub implementation)
// =============================================================================

const TCP_PORT: u16 = 7777;

pub struct TcpConnection {
    pub socket: u32,
    pub connected: bool,
    pub rx_buffer: [u8; 256],
    pub rx_len: usize,
    pub tx_buffer: [u8; 512],
    pub tx_len: usize,
}

impl TcpConnection {
    pub fn new() -> Self {
        TcpConnection {
            socket: 0,
            connected: false,
            rx_buffer: [0; 256],
            rx_len: 0,
            tx_buffer: [0; 512],
            tx_len: 0,
        }
    }

    pub fn accept(&mut self) -> bool {
        // In bare-metal, this would call LwIP's tcp_accept()
        // Stub - real implementation needs BSP integration
        false
    }

    pub fn read(&mut self, buffer: &mut [u8]) -> usize {
        if !self.connected {
            return 0;
        }
        let len = core::cmp::min(buffer.len(), self.rx_len);
        buffer[..len].copy_from_slice(&self.rx_buffer[..len]);
        self.rx_len = 0;
        len
    }

    pub fn write(&mut self, data: &[u8]) -> usize {
        if !self.connected {
            return 0;
        }
        let len = core::cmp::min(data.len(), 512 - self.tx_len);
        self.tx_buffer[self.tx_len..][..len].copy_from_slice(&data[..len]);
        self.tx_len += len;
        len
    }

    pub fn flush(&mut self) {
        if self.connected && self.tx_len > 0 {
            // Would call LwIP's tcp_write()
            self.tx_len = 0;
        }
    }
}

// =============================================================================
// Tokenizer (Fixed-size, no heap)
// =============================================================================

// Qwen vocabulary size
const VOCAB_SIZE: usize = 151936;
// Maximum token length
const MAX_TOKEN_LEN: usize = 32;

#[repr(C)]
struct VocabEntry {
    token: [u8; MAX_TOKEN_LEN],
    token_len: u8,
}

pub struct Tokenizer {
    // In real implementation, vocab would be loaded from DDR4
    // For now, use simple ASCII fallback
}

impl Tokenizer {
    pub fn new() -> Self {
        Tokenizer {}
    }

    // Encode text to token IDs - no heap allocation
    // Uses fixed-size array for output
    pub fn encode(&self, text: &str, output: &mut [u32; 64]) -> usize {
        let mut count = 0;
        for c in text.chars() {
            if count < 64 {
                // Simple Unicode codepoint encoding
                // Real BPE would do proper word-piece splitting
                output[count] = c as u32;
                count += 1;
            }
        }
        // Add EOS token (151643)
        if count < 64 {
            output[count] = 151643;
            count += 1;
        }
        count
    }

    // Decode token IDs to string - writes to fixed buffer
    pub fn decode(&self, token_ids: &[u32], output: &mut [u8; 256]) -> usize {
        let mut len = 0;
        for &id in token_ids.iter().take(64) {
            if id == 151643 {
                break; // EOS
            }
            if let Some(c) = char::from_u32(id) {
                let mut buf = [0u8; 4];
                let s = c.encode_utf8(&mut buf);
                for b in s.bytes() {
                    if len < 256 {
                        output[len] = b;
                        len += 1;
                    }
                }
            }
        }
        len
    }
}

// =============================================================================
// Weight Loading (SD Card -> DDR4)
// =============================================================================

// DDR4 memory map
const MODEL_BASE: u32 = 0x1000_0000;  // 9B model weights
const FEEDER_BASE: u32 = 0x7000_0000; // 0.5B feeder weights
const LAYER_SIZE: usize = 262144;     // Number of elements per layer

#[repr(C)]
struct WeightHeader {
    magic: u32,           // 0x49535000 = "ISP\0"
    version: u32,
    model_type: u32,      // 0 = Qwen 9B, 1 = Feeder 0.5B
    layer_count: u32,
    embedding_size: u32,
    quantized: u32,        // 1 = ternary (1.58-bit)
    size_bytes: u64,
    checksum: u32,
}

pub struct SdReader;

impl SdReader {
    pub fn new() -> Self {
        SdReader
    }

    // Read weight header
    pub fn read_header(&mut self) -> Result<WeightHeader, LoadError> {
        // Stub - real implementation uses Xilinx SD controller
        unsafe { Ok(core::mem::zeroed()) }
    }

    // Read into DDR4
    pub fn read_into(&mut self, dest: u32, len: usize) -> Result<(), LoadError> {
        // Stub - real implementation uses DMA
        Ok(())
    }
}

#[derive(Debug)]
pub enum LoadError {
    InvalidMagic,
    NotQuantized,
    IoError,
    ChecksumMismatch,
}

// =============================================================================
// Weight Streaming (DDR4 -> FPGA via AXI Mailbox)
// =============================================================================

pub struct WeightLoader;

impl WeightLoader {
    pub fn new() -> Self {
        WeightLoader
    }

    // Load layer weights from DDR4 and stream directly to FPGA via mailbox
    // Note: NO temp buffer - we stream directly to avoid 512KB stack overflow
    // layer_idx: which layer (0-31 for Qwen 9B)
    // layer_type: which weight matrix within the layer
    pub fn load_layer_weights(
        &mut self,
        dispatcher: &mut LayerDispatcher,
        layer_idx: u32,
        layer_type: LayerType,
    ) {
        let offset = MODEL_BASE + (layer_idx * LAYER_SIZE as u32 * 4);  // 4 matrices per layer

        // Trigger load_weights transaction in FPGA FSM
        dispatcher.state.control = 1;

        // Stream weights directly from DDR4 to FPGA mailbox
        for i in 0..LAYER_SIZE {
            let addr = offset + (i as u32 * 2);
            // Read directly from DDR4
            let value = unsafe { core::ptr::read_volatile(addr as *const u16) as i32 };
            // Write directly to FPGA mailbox
            dispatcher.state.write_addr = i as u32;
            dispatcher.state.write_data = value;
            dispatcher.state.write_en = 1;
            dispatcher.state.write_en = 0;
        }
    }
}

// =============================================================================
// Ternary Decoding (4 values per byte)
// =============================================================================

// Unpack 4 ternary values from 1 byte
// Encoding: 2 bits per value
// 00 = 0, 01 = 1, 10 = -1, 11 = reserved/error
#[inline(always)]
pub fn unpack_ternary(byte: u8) -> [i16; 4] {
    let b0 = (byte & 0x03) as i16;
    let b1 = ((byte >> 2) & 0x03) as i16;
    let b2 = ((byte >> 4) & 0x03) as i16;
    let b3 = ((byte >> 6) & 0x03) as i16;

    [
        if b0 == 2 { -1 } else { b0 },
        if b1 == 2 { -1 } else { b1 },
        if b2 == 2 { -1 } else { b2 },
        if b3 == 2 { -1 } else { b3 },
    ]
}

// Ternary multiply: result += weight * input
// Since weight is -1, 0, or 1:
//   weight == 1:  result += input
//   weight == -1: result -= input
//   weight == 0:  skip
#[inline(always)]
pub fn ternary_mac(acc: i32, weight: i16, input: i16) -> i32 {
    match weight {
        1 => acc + input as i32,
        -1 => acc - input as i32,
        _ => acc,
    }
}

// =============================================================================
// Layer Dispatcher (ARM -> FPGA via MMIO)
// =============================================================================

pub struct LayerDispatcher<'a> {
    state: &'a mut State,
}

impl<'a> LayerDispatcher<'a> {
    pub fn new(state: &'a mut State) -> Self {
        LayerDispatcher { state }
    }

    // Stream input activations to FPGA via MMIO mailbox
    // control=5 triggers load_input transaction in neuralcore.ebv
    pub fn send_input(&mut self, data: &[i16]) {
        self.state.control = 5;  // Set control = 5 for load_input transaction
        for (i, &value) in data.iter().take(262144).enumerate() {
            self.state.write_addr = i as u32;
            self.state.write_data = value as i32;
            self.state.write_en = 1;  // Pulse write enable
            self.state.write_en = 0;
        }
    }

    // Trigger FPGA to process a layer (control=20 triggers begin_forward)
    pub fn execute_layer(&mut self, layer_type: LayerType) {
        self.state.opcode = layer_type as u32;
        self.state.control = 20;  // begin_forward: [control == 20 && status == 0]
    }

    // Wait for layer to complete (status == 2 means done)
    pub fn wait_complete(&mut self) {
        while self.state.status != 2 {
            core::hint::spin_loop();
        }
        self.state.status = 0;  // Reset status for next operation
    }

    // Read result from FPGA scratch buffer via MMIO mailbox
    // control=25 triggers read_result transaction in neuralcore.ebv
    pub fn read_result(&mut self, offset: usize) -> i16 {
        self.state.control = 25;  // Set control = 25 for read_result transaction
        self.state.write_addr = offset as u32;
        self.state.read_en = 1;   // Trigger read
        let result = self.state.read_data as i16;
        self.state.read_en = 0;   // Reset read enable
        result
    }
}

// =============================================================================
// Transaction Runner (Brief State Machine)
// =============================================================================

pub struct TransactionRunner<'a> {
    state: &'a mut State,
}

impl<'a> TransactionRunner<'a> {
    pub fn new(state: &'a mut State) -> Self {
        TransactionRunner { state }
    }

    pub fn sync_hw(&mut self) -> bool {
        if self.state.control != ((self.state.control) & 0xFF) as u32 {
            self.state.control = self.state.control & 0xFF;
            true
        } else {
            false
        }
    }

    pub fn load_input(&mut self) -> bool {
        if self.state.control == 1 {
            self.state.kernel_state = 2;
            true
        } else {
            false
        }
    }

    // Execute full forward pass through one layer
    pub fn execute_layer(&mut self, dispatcher: &mut LayerDispatcher, layer: LayerType) {
        // Trigger FPGA
        dispatcher.execute_layer(layer);
        // Wait for completion
        dispatcher.wait_complete();
        self.state.status = 2;
    }
}

// =============================================================================
// Fixed-size Token Array (no heap)
// =============================================================================

// Use plain array instead of Vec
pub struct TokenArray {
    data: [u32; 64],
    len: usize,
}

impl TokenArray {
    pub fn new() -> Self {
        TokenArray {
            data: [0u32; 64],
            len: 0,
        }
    }

    pub fn push(&mut self, token: u32) {
        if self.len < 64 {
            self.data[self.len] = token;
            self.len += 1;
        }
    }

    pub fn as_slice(&self) -> &[u32] {
        &self.data[..self.len]
    }
}

// =============================================================================
// Main Entry Point
// =============================================================================

#[no_mangle]
pub extern "C" fn main() -> ! {
    let mut uart_buf = UartBuffer::new();
    uart_buf.write_str("IMP Kernel v0.2 initializing...\r\n");
    uart_buf.flush();

    // Get MMIO state
    let state = unsafe { State::get() };
    uart_buf.write_str("MMIO ready\r\n");
    uart_buf.flush();

    // Initialize tokenizer
    let tokenizer = Tokenizer::new();
    uart_buf.write_str("Tokenizer ready\r\n");
    uart_buf.flush();

    // Initialize dispatcher and runner
    let mut dispatcher = LayerDispatcher::new(state);
    let mut runner = TransactionRunner::new(state);

    uart_buf.write_str("IMP ready. Listening on port 7777\r\n");
    uart_buf.flush();

    // Fixed-size token storage (no Vec)
    let mut input_tokens = [0u32; 64];
    let mut output_tokens = [0u32; 64];

    // Main loop
    loop {
        // Accept TCP connection
        let mut conn = TcpConnection::new();
        if conn.accept() {
            uart_buf.write_str("Connection established\r\n");
            uart_buf.flush();

            // Read prompt (fixed-size buffer)
            let mut rx_buf = [0u8; 256];
            let len = conn.read(&mut rx_buf);

            if len > 0 {
                // Convert to string safely
                let prompt_len = core::cmp::min(len, 255);
                let prompt = core::str::from_utf8(&rx_buf[..prompt_len])
                    .unwrap_or("");

                uart_buf.write_str("Prompt: ");
                uart_buf.write_str(prompt);
                uart_buf.write_str("\r\n");
                uart_buf.flush();

                // Tokenize (no heap)
                let token_count = tokenizer.encode(prompt, &mut input_tokens);

                // Initialize weight loader
                let mut weight_loader = WeightLoader::new();

                // Process each token through the neural network
                // IMPORTANT: We must stream weights BEFORE input for each layer
                for i in 0..token_count {
                    let token = input_tokens[i] as i16;

                    // CRITICAL: Load the layer's weights from DDR4 to FPGA first
                    // Without this, weight_buffer is all zeros and output is meaningless
                    weight_loader.load_layer_weights(&mut dispatcher, i as u32, LayerType::Attention);

                    // Stream input activations
                    dispatcher.send_input(&[token]);

                    // Execute the layer
                    dispatcher.execute_layer(LayerType::Attention);
                    dispatcher.wait_complete();
                }

                // Read output tokens
                for i in 0..64 {
                    output_tokens[i] = dispatcher.read_result(i) as u32;
                }

                // Decode to fixed buffer
                let mut response_bytes = [0u8; 256];
                let response_len = tokenizer.decode(&output_tokens, &mut response_bytes);

                // Send response
                let response = core::str::from_utf8(&response_bytes[..response_len])
                    .unwrap_or("");
                conn.write(response.as_bytes());
                conn.flush();

                uart_buf.write_str("Response sent\r\n");
                uart_buf.flush();
            }
        }

        // Run idle transaction
        runner.sync_hw();
    }
}

// =============================================================================
// Panic Handler
// =============================================================================

#[panic_handler]
fn panic(info: &core::panic::PanicInfo) -> ! {
    uart_puts("PANIC: ");
    if let Some(loc) = info.location() {
        // Use uart_puts instead of format!
        let file = loc.file();
        let line = loc.line();
        let col = loc.column();
        // Write directly to UART without format!
        uart_puts(file);
        uart_putc(':');
        // Simple number output
        uart_puts(" TODO: num ");
    }
    loop {
        core::hint::spin_loop();
    }
}

// =============================================================================
// Start
// =============================================================================

#[link_section = ".text.start"]
pub extern "C" fn _start() -> ! {
    main()
}