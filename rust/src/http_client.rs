//! Shared TLS-provider setup; callers retain their own network/consent policy.
//!
//! Reqwest 0.13's `rustls-no-provider` requires explicit provider installation
//! before *any* client is built, including clients restricted to loopback HTTP.
//! Keep Rustls certificate/hostname verification and platform roots unchanged.

use std::sync::Once;

pub fn builder() -> reqwest::ClientBuilder {
    static INSTALL_PROVIDER: Once = Once::new();
    INSTALL_PROVIDER.call_once(|| {
        // Installation is process-wide. Another caller may already have
        // installed Ring; Rustls permits only the first installation to win.
        let _ = rustls::crypto::ring::default_provider().install_default();
    });
    reqwest::Client::builder()
}
