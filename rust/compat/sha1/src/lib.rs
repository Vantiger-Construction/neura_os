//! Neura-local forwarding adapter for the existing WebSocket handshake calls.
//! All hashing is implemented by the unmodified RustCrypto 0.11 crate.
#![no_std]
#![forbid(unsafe_code)]

pub use sha1_upstream::*;
