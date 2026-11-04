//! Real TLS handshakes on loopback with public, synthetic test-only keys.
//! No provider endpoint, installed certificate store or user data is touched.

use neura_swarm::http_client;
use rustls::pki_types::{CertificateDer, PrivateKeyDer, PrivatePkcs8KeyDer};
use std::{net::SocketAddr, sync::Arc, time::Duration};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio_rustls::TlsAcceptor;

const CA: &[u8] = include_bytes!("fixtures/tls/ca.der");
const CERT: &[u8] = include_bytes!("fixtures/tls/localhost.der");
const KEY: &[u8] = include_bytes!("fixtures/tls/localhost-key.der");

async fn server() -> (SocketAddr, tokio::task::JoinHandle<bool>) {
    let config = rustls::ServerConfig::builder_with_provider(Arc::new(
        rustls::crypto::ring::default_provider(),
    ))
    .with_safe_default_protocol_versions()
    .unwrap()
    .with_no_client_auth()
    .with_single_cert(
        vec![CertificateDer::from(CERT.to_vec())],
        PrivateKeyDer::Pkcs8(PrivatePkcs8KeyDer::from(KEY.to_vec())),
    )
    .unwrap();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let task = tokio::spawn(async move {
        tokio::time::timeout(Duration::from_secs(5), async move {
            let (socket, _) = listener.accept().await.unwrap();
            let Ok(mut stream) = TlsAcceptor::from(Arc::new(config)).accept(socket).await else {
                return false;
            };
            let mut request = [0_u8; 1024];
            let count = stream.read(&mut request).await.unwrap();
            assert!(request[..count].starts_with(b"GET / HTTP/1.1\r\n"));
            stream
                .write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK")
                .await
                .unwrap();
            true
        })
        .await
        .expect("loopback TLS handshake must finish")
    });
    (address, task)
}

fn client(address: SocketAddr, trust_test_ca: bool) -> reqwest::Client {
    let builder = http_client::builder()
        .no_proxy()
        .redirect(reqwest::redirect::Policy::none())
        .timeout(Duration::from_secs(5))
        .resolve("localhost", address);
    let builder = if trust_test_ca {
        // This synthetic CA is added only to this test's client, never globally.
        builder.tls_certs_merge([reqwest::Certificate::from_der(CA).unwrap()])
    } else {
        builder
    };
    builder
        .build()
        .expect("explicit Ring provider permits client construction")
}

#[tokio::test]
async fn trusted_local_tls_endpoint_completes_a_real_request() {
    let (address, task) = server().await;
    let reply = client(address, true)
        .get(format!("https://localhost:{}/", address.port()))
        .send()
        .await
        .unwrap();
    assert_eq!(reply.status(), reqwest::StatusCode::OK);
    assert_eq!(reply.text().await.unwrap(), "OK");
    assert!(task.await.unwrap());
}

#[tokio::test]
async fn untrusted_test_ca_is_rejected_before_http() {
    let (address, task) = server().await;
    let error = client(address, false)
        .get(format!("https://localhost:{}/", address.port()))
        .send()
        .await
        .unwrap_err();
    assert!(error.is_connect() && !error.is_timeout(), "{error:?}");
    assert!(!task.await.unwrap());
}

#[tokio::test]
async fn trusted_ca_cannot_override_a_hostname_mismatch() {
    let (address, task) = server().await;
    // The fixture covers localhost only, not this IP literal.
    let error = client(address, true)
        .get(format!("https://{address}/"))
        .send()
        .await
        .unwrap_err();
    assert!(error.is_connect() && !error.is_timeout(), "{error:?}");
    assert!(!task.await.unwrap());
}
