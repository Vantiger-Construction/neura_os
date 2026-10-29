//! Exercise the exact high-level hash operations used by FRB and WebSocket IPC.
use md5_compat::{Digest, Md5};
use sha1_compat::Sha1;

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

#[test]
fn rustcrypto_known_vectors_and_frb_indexed_digest_stay_stable() {
    for (input, md5, sha1) in [
        (
            "",
            "d41d8cd98f00b204e9800998ecf8427e",
            "da39a3ee5e6b4b0d3255bfef95601890afd80709",
        ),
        (
            "abc",
            "900150983cd24fb0d6963f7d28e17f72",
            "a9993e364706816aba3e25717850c26c9cd0d89d",
        ),
        (
            "abcdefghijklmnopqrstuvwxyz",
            "c3fcd3d76192e4007dfb496cca67e13b",
            "32d10c7b8cf96570ca04ce37f2a19d84240d3a89",
        ),
    ] {
        assert_eq!(hex(&Md5::digest(input)), md5);
        assert_eq!(hex(&Sha1::digest(input)), sha1);
    }
    // FRB hashes item text, then takes the first eight bytes as a little-endian ID.
    let digest = Md5::digest("abc");
    assert_eq!(
        u64::from_le_bytes(digest[..8].try_into().unwrap()),
        0xb04fd23c98500190
    );
}

#[test]
fn incremental_hashing_crosses_padding_and_block_boundaries() {
    let input = vec![b'a'; 1_000_000];
    for chunk_size in [1, 55, 56, 63, 64, 65, 127, 128, 129, 4096] {
        let mut md5 = Md5::default();
        let mut sha1 = Sha1::default();
        for chunk in input.chunks(chunk_size) {
            md5.update(chunk);
            sha1.update(chunk);
        }
        assert_eq!(hex(&md5.finalize()), "7707d6ae4e027c70eea2a935c2296f21");
        assert_eq!(
            hex(&sha1.finalize()),
            "34aa973cd4c4daa4f61eeb2bdbad27316534016f"
        );
    }
}

#[test]
fn websocket_rfc6455_accept_digest_stays_stable() {
    // RFC 6455 section 1.3: base64 of this digest is s3pPLMBiTxaQ9kYGzzhZRbK+xOo=.
    let mut hash = Sha1::default();
    hash.update(b"dGhlIHNhbXBsZSBub25jZQ==");
    hash.update(b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11");
    assert_eq!(
        hex(&hash.finalize()),
        "b37a4f2cc0624f1690f64606cf385945b2bec4ea"
    );
}
