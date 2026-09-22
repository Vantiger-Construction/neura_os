//! A ready `Transport` backed by `reqwest`'s blocking client.
//!
//! Compiled only under the `reqwest-transport` feature so the core crate stays
//! dependency-light. Enable with `cargo build --features reqwest-transport`.

use crate::brain::{BrainError, Transport};

pub struct ReqwestTransport {
    client: reqwest::blocking::Client,
}

impl ReqwestTransport {
    pub fn new() -> Self {
        Self { client: reqwest::blocking::Client::new() }
    }
}

impl Default for ReqwestTransport {
    fn default() -> Self {
        Self::new()
    }
}

impl Transport for ReqwestTransport {
    fn post_json(&self, url: &str, body: &str) -> Result<String, BrainError> {
        ensure_loopback(url)?;
        let resp = self
            .client
            .post(url)
            .header("content-type", "application/json")
            .body(body.to_string())
            .send()
            .map_err(|e| BrainError::Transport(e.to_string()))?
            .error_for_status()
            .map_err(|e| BrainError::Transport(e.to_string()))?;
        resp.text().map_err(|e| BrainError::Transport(e.to_string()))
    }
}


/// The built-in transport is intentionally local-only. Cloud requests must go
/// through Neura's visible fresh-approval router, never this sidecar shortcut.
fn ensure_loopback(url: &str) -> Result<(), BrainError> {
    let parsed =
        reqwest::Url::parse(url).map_err(|error| BrainError::Transport(error.to_string()))?;
    let host = parsed
        .host_str()
        .ok_or_else(|| BrainError::Transport("model endpoint has no host".to_string()))?;
    let loopback = host.eq_ignore_ascii_case("localhost")
        || host
            .parse::<std::net::IpAddr>()
            .is_ok_and(|address| address.is_loopback());
    if !loopback {
        return Err(BrainError::Transport(
            "remote model endpoints require Neura's fresh-approval router".to_string(),
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_loopback_model_endpoints() {
        assert!(ensure_loopback("http://127.0.0.1:1234/v1/chat/completions").is_ok());
        assert!(ensure_loopback("http://[::1]:1234/v1/chat/completions").is_ok());
        assert!(ensure_loopback("http://localhost:1234/v1/chat/completions").is_ok());
    }

    #[test]
    fn rejects_direct_cloud_model_endpoints() {
        let error = ensure_loopback("https://api.example.com/v1/chat/completions")
            .expect_err("direct cloud endpoints must be blocked");
        assert!(error
            .to_string()
            .contains("fresh-approval router"));
    }
}
