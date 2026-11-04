# Synthetic TLS fixtures

These public test-only DER files exercise a real local TLS handshake. They are
not application credentials and must never be installed in a device trust store.

- `ca.der`: synthetic P-256 test CA, serial 1. Its signing key is not retained.
- `localhost.der`: CA-signed P-256 server certificate, serial 2, SAN `localhost`
  only, server-auth extended usage. Valid January 1, 2020–January 1, 2120.
- `localhost-key.der`: deliberately public PKCS#8 key for that test server.

The tests bind only to an ephemeral IPv4 loopback port. They use the unmodified
production HTTP builder; only the positive and hostname-mismatch tests add this
CA to their individual clients. The default client must reject it, and trusting
the CA must not make a request to `127.0.0.1` pass hostname verification.
