//! IMP Bare-Metal Kernel for KV260
//! 
//! This is a `#![no_std]` crate compiled for bare-metal ARM64

#![no_std]
#![no_main]

include!("kernel.rs");

/// Entry point that startup.s calls
#[link_section = ".text.start"]
pub extern "C" fn _start() -> ! {
    // This will be called after stack is set up
    main()
}