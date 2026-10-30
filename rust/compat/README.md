# RustCrypto dependency migration

`GHSA-qwgh-2vcv-g2f7` flags the old `block-buffer` dependency brought in by
`digest 0.10`. The advisory's patched version is `block-buffer 0.12.1`:
https://github.com/advisories/GHSA-qwgh-2vcv-g2f7

The pinned `flutter_rust_bridge_macros 2.12.0` requires `md-5 ^0.10.6`.
`axum 0.7.9` and `tungstenite 0.24.0` require `sha1 ^0.10`. Those upstream
constraints cannot resolve the patched buffer generation. Updating the entire
Flutter bridge or WebSocket framework would also change unrelated APIs.

The two **local, unpublished** `0.10.99` adapter packages satisfy those
consumers' version constraints and re-export the unmodified registry releases
`md-5 0.11.0` and `sha1 0.11.0`. They contain no hashing implementation. Their
version identifies Neura's adapter; it is not an upstream RustCrypto release.
The upstream packages retain their registry identities and checksums in the
lockfile. They resolve `digest 0.11.3` and `block-buffer 0.12.1`; each adapter
also requires the patched buffer floor to prevent a later downgrade.

This is a narrow migration for the `Digest`/`Md5` calls in FRB's
`attr_external.rs` and the `Digest`/`Sha1` handshake calls in Axum's
`extract/ws.rs` and Tungstenite's `handshake/mod.rs`. The adapters re-export the
**0.11 API** and do not promise full compatibility with every 0.10 API or
feature. New consumers must use the upstream crates directly. MD5 remains an
FRB symbol hash and SHA-1 remains part of the WebSocket protocol; neither is
introduced for passwords, memory encryption or authentication policy.

`rust/tests/digest_compat.rs` checks known digest vectors, padding boundaries,
incremental updates, FRB's indexed digest use and the RFC 6455 handshake vector.
The existing IPC and native-session tests exercise the actual consumers.

Verify from the repository root:

```sh
cargo test --manifest-path rust/Cargo.toml --locked --all-targets
cargo clippy --manifest-path rust/Cargo.toml --locked --all-targets -- -D warnings
cargo tree --manifest-path rust/Cargo.toml --locked -i block-buffer
python3 tools/security/scan_dependencies.py --scanner /path/to/osv-scanner --output /tmp/neura-audit
```

The audit policy and all finding handling remain unchanged. Remove an adapter
when its upstream consumer supports the patched RustCrypto generation, then
regenerate the lockfile and repeat these checks.
