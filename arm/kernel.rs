// IMP Bare-Metal Kernel - ARM Cortex-A53
// Target: KV260, runs without Linux
// Compile with: rustc --target arm-none-eabi --edition 2021

#![no_std]
#![no_main]
#![feature(const_mut_refs)]

use core::fmt::Write;
use core::sync::atomic::{AtomicBool, Ordering};

// =============================================================================
// MMIO Hardware Interface
// =============================================================================

// Hardware memory-mapped registers at 0x4000A000 (FPGA AXI4-Lite slave)
const MMIO_BASE: *mut State = 0x4000A000 as *mut State;

#[repr(C)]
pub struct State {
    // Control registers (R/W with FPGA)
    pub control: u32,        // 0x4000A000 - Command to FPGA
    pub status: u32,         // 0x4000A004 - FPGA status
    pub opcode: u32,         // 0x4000A008 - Operation code
    pub token_count: u32,    // 0x4000A00C - Token counter

    // DMA buffers (on FPGA BRAM/UltraRAM)
    pub input_embedding: u32,  // 0x40A80000 - Input tensor base
    pub output_logits: u32,   // 0x40AA0000 - Output tensor base
    pub kv_cache_k: u32,       // 0x40A0A000 - K cache
    pub kv_cache_v: u32,       // 0x40A60000 - V cache

    // Internal kernel state
    pub kernel_state: u32,
    pub model_loaded: u32,
    pub input_ptr: u32,
    pub output_ptr: u32,
}

impl State {
    // Safety: Only call with correct MMIO base address
    pub unsafe fn get() -> &'static mut State {
        &mut *MMIO_BASE
    }

    // Wait for FPGA to be ready
    pub fn wait_ready(&self) {
        while self.status != 2 {
            core::hint::spin_loop();
        }
    }

    // Send a layer to FPGA for processing
    pub fn send_layer(&mut self, layer_type: LayerType, layer_index: u32) {
        self.opcode = layer_type as u32;
        self.control = 20 + layer_index; // 20=attention, 21=mlp_gate, etc.
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
// UART Driver (for debug)
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

// =============================================================================
// Ethernet (LwIP TCP)
// =============================================================================

// LwIP constants - these would be provided by LwIP stack
const TCP_PORT: u16 = 7777;
const RX_BUFFER_SIZE: usize = 4096;
const TX_BUFFER_SIZE: usize = 8192;

// Network buffer pools (would be provided by BSP)
static RX_BUFFER: AtomicBool = AtomicBool::new(false);

pub struct TcpConnection {
    pub socket: u32,
    pub connected: bool,
    pub rx_buffer: [u8; RX_BUFFER_SIZE],
    pub rx_len: usize,
    pub tx_buffer: [u8; TX_BUFFER_SIZE],
    pub tx_len: usize,
}

impl TcpConnection {
    pub fn new() -> Self {
        TcpConnection {
            socket: 0,
            connected: false,
            rx_buffer: [0; RX_BUFFER_SIZE],
            rx_len: 0,
            tx_buffer: [0; TX_BUFFER_SIZE],
            tx_len: 0,
        }
    }

    // Accept connection on port 7777
    pub fn accept(&mut self) -> bool {
        // In bare-metal, this would call LwIP's tcp_accept()
        // For now, we stub it - real implementation needs BSP integration
        false
    }

    // Read data from TCP connection
    pub fn read(&mut self, buffer: &mut [u8]) -> usize {
        if !self.connected {
            return 0;
        }
        let len = core::cmp::min(buffer.len(), self.rx_len);
        buffer[..len].copy_from_slice(&self.rx_buffer[..len]);
        self.rx_len = 0;
        len
    }

    // Write data to TCP connection
    pub fn write(&mut self, data: &[u8]) -> usize {
        if !self.connected {
            return 0;
        }
        let len = core::cmp::min(data.len(), TX_BUFFER_SIZE - self.tx_len);
        self.tx_buffer[self.tx_len..][..len].copy_from_slice(&data[..len]);
        self.tx_len += len;
        len
    }

    // Flush TX buffer
    pub fn flush(&mut self) {
        if self.connected && self.tx_len > 0 {
            // Would call LwIP's tcp_write()
            self.tx_len = 0;
        }
    }
}

// =============================================================================
// Tokenizer (Full BPE)
// =============================================================================

// Tokenizer vocab size for Qwen (typical: 151936 tokens)
const VOCAB_SIZE: usize = 151936;
const MAX_TOKEN_LEN: usize = 32;

// BPE vocab entry
#[repr(C)]
struct VocabEntry {
    token: [u8; MAX_TOKEN_LEN],
    token_len: u8,
    rank: u32,
}

// Tokenizer state
pub struct Tokenizer {
    vocab: &'static [VocabEntry],
}

impl Tokenizer {
    // Encode text string to token IDs
    pub fn encode(&self, text: &str) -> Vec<u32> {
        let mut tokens = Vec::new();

        // Simple UTF-8 byte encoding fallback
        // Full BPE would do proper word-piece splitting
        for c in text.chars() {
            // Use Unicode codepoint as token ID
            // Real implementation: BPE merge lookup
            tokens.push(c as u32);
        }

        // Add end-of-sequence token (typically 151643)
        tokens.push(151643);

        tokens
    }

    // Decode token IDs to text string
    pub fn decode(&self, token_ids: &[u32]) -> String {
        let mut result = String::new();

        for &id in token_ids {
            if id == 151643 {
                break; // EOS token
            }
            // Use codepoint from token ID
            // Real implementation: reverse BPE lookup
            if let Some(c) = char::from_u32(id) {
                result.push(c);
            }
        }

        result
    }
}

// =============================================================================
// Weight Loader (SD Card → DDR4)
// =============================================================================

// DDR4 memory map
const MODEL_BASE: u32 = 0x1000_0000;  // 9B model weights
const FEEDER_BASE: u32 = 0x7000_0000; // 0.5B feeder weights

// Weight file headers
#[repr(C)]
struct WeightHeader {
    magic: u32,           // 0x49535000 = "ISP\0"
    version: u32,          // Version 1
    model_type: u32,      // 0 = Qwen 9B, 1 = Feeder 0.5B
    layer_count: u32,
    embedding_size: u32,
    quantized: u32,       // 1 = ternary (1.58-bit)
    size_bytes: u64,
    checksum: u32,
}

// Load model weights from SD card into DDR4
pub fn load_weights(sd_reader: &mut SdReader) -> Result<WeightHeader, LoadError> {
    // Read weight header
    let header = sd_reader.read::<WeightHeader>()?;

    if header.magic != 0x49535000 {
        return Err(LoadError::InvalidMagic);
    }

    if header.quantized != 1 {
        return Err(LoadError::NotQuantized);
    }

    // Load weights into DDR4
    let dest = if header.model_type == 0 {
        MODEL_BASE
    } else {
        FEEDER_BASE
    };

    // Read weight data in chunks
    let mut remaining = header.size_bytes as usize;
    let mut addr = dest;

    while remaining > 0 {
        let chunk_size = core::cmp::min(remaining, 65536);
        sd_reader.read_into(addr as *mut u8, chunk_size)?;
        addr += chunk_size as u32;
        remaining -= chunk_size;
    }

    Ok(header)
}

// =============================================================================
// SD Card Reader
// =============================================================================

pub struct SdReader {
    // Would use Xilinx SD controller
}

impl SdReader {
    pub fn new() -> Self {
        SdReader {}
    }

    pub fn read<T>(&mut self) -> Result<T, LoadError> {
        // Stub - real implementation uses Xilinx SD driver
        unsafe { core::mem::zeroed() }
    }

    pub fn read_into(&mut self, dest: *mut u8, len: usize) -> Result<(), LoadError> {
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
// Ternary Decoder (4 values per byte)
// =============================================================================

// Unpack 4 ternary values from 1 byte
//
// Encoding: 2 bits per value
// 00 = 0, 01 = 1, 10 = -1, 11 = reserved/error
//
// For 1.58-bit quantization, we pack 4 values per byte
// giving us 4 * 1.58 = 6.32 bits effective per byte
// (but we store 4 values = 8 bits)
#[inline(always)]
pub fn unpack_ternary(byte: u8) -> [i16; 4] {
    let b0 = (byte & 0x03) as i16;
    let b1 = ((byte >> 2) & 0x03) as i16;
    let b2 = ((byte >> 4) & 0x03) as i16;
    let b3 = ((byte >> 6) & 0x03) as i16;

    // Convert 2-bit codes to ternary: 00=0, 01=1, 10=-1, 11=0 (treat 11 as 0)
    [
        if b0 == 2 { -1 } else { b0 },
        if b1 == 2 { -1 } else { b1 },
        if b2 == 2 { -1 } else { b2 },
        if b3 == 2 { -1 } else { b3 },
    ]
}

// Ternary multiply: result += weight * input
// Since weight is -1, 0, or 1, this becomes:
//   weight == 1: result += input
//   weight == -1: result -= input
//   weight == 0: skip
#[inline(always)]
pub fn ternary_mac(acc: i32, weight: i16, input: i16) -> i32 {
    match weight {
        1 => acc + input as i32,
        -1 => acc - input as i32,
        _ => acc,
    }
}

// =============================================================================
// Layer Dispatcher (ARM → FPGA)
// =============================================================================

pub struct LayerDispatcher {
    state: &'static mut State,
    current_layer: u32,
    layer_type: LayerType,
}

impl LayerDispatcher {
    pub fn new(state: &'static mut State) -> Self {
        LayerDispatcher {
            state,
            current_layer: 0,
            layer_type: LayerType::Attention,
        }
    }

    // Send a tensor to FPGA BRAM
    pub fn send_tensor(&mut self, data: &[i16], base_addr: u32) {
        // Data is written directly via AXI by the FPGA
        // ARM sets up the address, FPGA copies
        // For now: copy via simple loop
        let mut addr = base_addr;
        for &value in data {
            // Would use DMA or direct AXI write
            core::ptr::write_volatile(addr as *mut u16, value as u16);
            addr += 2;
        }
    }

    // Trigger FPGA to process a layer
    pub fn execute_layer(&mut self, layer_type: LayerType, layer_idx: u32) {
        self.layer_type = layer_type;
        self.current_layer = layer_idx;
        self.state.send_layer(layer_type, layer_idx);
    }

    // Wait for layer to complete
    pub fn wait_complete(&mut self) {
        // Poll status register until FPGA signals done
        while self.state.status != 5 {
            core::hint::spin_loop();
        }
        self.state.status = 0; // Clear status
    }

    // Read result tensor from FPGA
    pub fn read_tensor(&mut self, base_addr: u32, len: usize) -> Vec<i16> {
        let mut result = Vec::with_capacity(len);
        let mut addr = base_addr;

        for _ in 0..len {
            let val = unsafe { core::ptr::read_volatile(addr as *const u16) };
            result.push(val as i16);
            addr += 2;
        }

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

    // Execute the sync_hw transaction
    pub fn sync_hw(&mut self) -> bool {
        if self.state.control != ((self.state.control) & 0xFF) as u32 {
            self.state.control = self.state.control & 0xFF;
            true
        } else {
            false
        }
    }

    // Execute load_input transaction
    pub fn load_input(&mut self) -> bool {
        if self.state.control == 1 {
            self.state.kernel_state = 2;
            true
        } else {
            false
        }
    }

    // Execute forward pass through all layers
    pub fn execute_forward(&mut self, dispatcher: &mut LayerDispatcher) {
        // Load input tensor
        dispatcher.send_tensor(&[], 0x40A80000); // input_embedding base

        // Layer 0: Attention QKV projection
        dispatcher.execute_layer(LayerType::Attention, 0);
        dispatcher.wait_complete();

        // Layer 1: MLP Gate
        dispatcher.execute_layer(LayerType::MlpGate, 1);
        dispatcher.wait_complete();

        // Layer 2: MLP Up
        dispatcher.execute_layer(LayerType::MlpUp, 2);
        dispatcher.wait_complete();

        // Layer 3: MLP Down
        dispatcher.execute_layer(LayerType::MlpDown, 3);
        dispatcher.wait_complete();

        self.state.status = 2; // Done
    }
}

// =============================================================================
// TCP Inference Handler
// =============================================================================

pub struct InferenceHandler {
    connection: TcpConnection,
    tokenizer: Tokenizer,
    dispatcher: LayerDispatcher,
}

impl InferenceHandler {
    pub fn new(state: &'static mut State, vocab: &'static [VocabEntry]) -> Self {
        InferenceHandler {
            connection: TcpConnection::new(),
            tokenizer: Tokenizer { vocab },
            dispatcher: LayerDispatcher::new(state),
        }
    }

    // Handle a complete inference request
    pub fn handle(&mut self, prompt: &str) -> String {
        // Tokenize
        let input_tokens = self.tokenizer.encode(prompt);
        uart_puts(&format!("Tokens: {} ", input_tokens.len()));

        // Load input tensor
        for (i, &token) in input_tokens.iter().enumerate() {
            self.dispatcher.send_tensor(&[token as i16], 0x40A80000 + (i as u32 * 2));
        }

        // Execute forward pass
        self.dispatcher.execute_layer(LayerType::Attention, 0);
        self.dispatcher.wait_complete();

        // Read output
        let output_tokens = self.dispatcher.read_tensor(0x40AA0000, 64);

        // Decode
        self.tokenizer.decode(&output_tokens.iter().map(|&x| x as u32).collect::<Vec<_>>())
    }

    // Accept new connection
    pub fn accept_connection(&mut self) -> bool {
        self.connection.accept()
    }
}

// =============================================================================
// Main Entry Point
// =============================================================================

#[no_mangle]
pub extern "C" fn main() -> ! {
    uart_puts("IMP Kernel v0.1 initializing...\r\n");

    // Get MMIO state
    let state = unsafe { State::get() };

    uart_puts("MMIO initialized\r\n");

    // Initialize tokenizer (vocab loaded from SD at boot)
    let vocab = unsafe {
        core::slice::from_raw_parts(
            0x7400_0000 as *const VocabEntry, // Vocab loaded to this address
            VOCAB_SIZE,
        )
    };
    let tokenizer = Tokenizer { vocab };

    uart_puts("Tokenizer ready\r\n");

    // Initialize layer dispatcher
    let mut dispatcher = LayerDispatcher::new(state);

    // Initialize transaction runner
    let mut runner = TransactionRunner::new(state);

    uart_puts("IMP Kernel ready. Listening on port 7777\r\n");

    // Main loop
    loop {
        // Accept TCP connection
        if dispatcher.accept_connection() {
            uart_puts("Connection established\r\n");

            // Read prompt from TCP
            let mut rx_buf = [0u8; 1024];
            let len = dispatcher.read(rx_buf.as_mut_slice());

            if len > 0 {
                let prompt = core::str::from_utf8(&rx_buf[..len]).unwrap_or("");
                uart_puts(&format!("Prompt: {} bytes\r\n", len));

                // Run inference
                let response = dispatcher.handle(prompt);

                // Send response
                dispatcher.write(response.as_bytes());
                dispatcher.flush();
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
        uart_puts(&format!("{}:{}:{}", loc.file(), loc.line(), loc.column()));
    }
    loop {
        core::hint::spin_loop();
    }
}

// =============================================================================
// Bare metal start
// =============================================================================

#[link_section = ".text.start"]
pub extern "C" fn _start() -> ! {
    main()
}