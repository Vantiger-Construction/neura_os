//! Coordinates the swarm's two concurrent agents for a single chat turn.
//! The existing persona-responder call stays entirely in Dart
//! (`NeuraAiService.streamReply`); this only runs the two *new* agents,
//! side by side, once the responder's reply text is known.

use crate::agents::critic::{self, CriticVerdict};
use crate::agents::memory::{self, MemoryFact};

pub struct SwarmOutcome {
    pub verdict: CriticVerdict,
    pub facts: Vec<MemoryFact>,
}

/// Runs the critic and memory-extractor agents concurrently (not
/// sequentially) via `tokio::join!`. Either agent failing (network error,
/// malformed model output) degrades to its safe default rather than failing
/// the whole turn -- a swarm agent hiccup should never be visible as an
/// error in the chat UI, since the primary reply has already been shown by
/// the time this runs.
pub async fn handle_turn(
    base_url: &str,
    api_key: &str,
    transcript: &str,
    draft_reply: &str,
    user_message: &str,
) -> SwarmOutcome {
    let critic_fut = critic::review(base_url, api_key, transcript, draft_reply);
    let memory_fut = memory::extract(base_url, api_key, user_message, draft_reply);

    let (critic_result, memory_result) = tokio::join!(critic_fut, memory_fut);

    SwarmOutcome {
        verdict: critic_result.unwrap_or(CriticVerdict::Pass),
        facts: memory_result.unwrap_or_default(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Read, Write};
    use std::net::TcpListener;
    use std::thread;
    use std::time::{Duration, Instant};

    /// Hand-rolled mock HTTP server (avoids adding a mocking crate as a new
    /// dependency). Accepts connections on a background thread, replies to
    /// each with a fixed JSON body after `delay_ms`, so the test can assert
    /// on real concurrency rather than trusting an untested `tokio::join!`.
    fn spawn_delayed_json_server(body: &'static str, delay_ms: u64) -> String {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind mock server");
        let addr = listener.local_addr().expect("mock server addr");

        thread::spawn(move || {
            for stream in listener.incoming() {
                let Ok(mut stream) = stream else { continue };
                thread::spawn(move || {
                    let mut buf = [0u8; 4096];
                    let _ = stream.read(&mut buf);
                    thread::sleep(Duration::from_millis(delay_ms));
                    let response = format!(
                        "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: {}\r\nconnection: close\r\n\r\n{}",
                        body.len(),
                        body
                    );
                    let _ = stream.write_all(response.as_bytes());
                    let _ = stream.flush();
                });
            }
        });

        format!("http://{addr}")
    }

    /// Proves the two agent calls actually run concurrently: each mocked
    /// response is delayed 300ms, so a sequential implementation would take
    /// ~600ms+ while `tokio::join!` should finish in ~300-450ms.
    #[tokio::test]
    async fn critic_and_memory_run_concurrently() {
        let base_url = spawn_delayed_json_server(
            r#"{"content": [{"type": "text", "text": "{\"verdict\": \"pass\"}"}]}"#,
            300,
        );

        let start = Instant::now();
        let outcome = handle_turn(
            &base_url,
            "test-key",
            "transcript",
            "draft reply",
            "user message",
        )
        .await;
        let elapsed = start.elapsed();

        assert_eq!(outcome.verdict, CriticVerdict::Pass);
        assert!(
            elapsed < Duration::from_millis(550),
            "expected concurrent execution (~300ms), took {elapsed:?} -- looks sequential"
        );
    }
}
