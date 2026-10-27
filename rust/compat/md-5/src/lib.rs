//! Neura-local forwarding adapter for Flutter Rust Bridge's MD5 hash call.
//! All hashing is implemented by the unmodified RustCrypto 0.11 crate.
#![no_std]
#![forbid(unsafe_code)]

pub use md5_upstream::*;
