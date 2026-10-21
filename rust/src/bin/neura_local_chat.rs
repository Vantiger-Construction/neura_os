//! Explicit terminal prototype, not an app startup provider or a voice service.
use neura_swarm::local_conversation::{
    LocalConversation, LocalConversationError, LocalTextGrant, MAX_INPUT_BYTES,
};
use std::io::{self, BufRead, Read, Write};
use tokio::sync::mpsc;
use zeroize::Zeroizing;

fn configuration() -> Result<u16, &'static str> {
    let arguments: Vec<String> = std::env::args().skip(1).collect();
    if arguments.len() != 3 || arguments[0] != "--allow-session-text" || arguments[1] != "--port" {
        return Err(
            "Use the reviewed Start-NeuraLocalConversation.ps1 launcher with -AllowSessionText.",
        );
    }
    arguments[2]
        .parse::<u16>()
        .ok()
        .filter(|port| *port != 0)
        .ok_or("A valid local server port is required.")
}

fn input_channel() -> mpsc::Receiver<Zeroizing<String>> {
    let (sender, receiver) = mpsc::channel(1);
    std::thread::spawn(move || {
        let input = io::stdin();
        let mut reader = input.lock();
        loop {
            let mut line = Zeroizing::new(String::new());
            let read = reader
                .by_ref()
                .take((MAX_INPUT_BYTES + 2) as u64)
                .read_line(&mut line);
            match read {
                Ok(0) | Err(_) => break,
                Ok(_) if line.len() > MAX_INPUT_BYTES + 1 => break,
                Ok(_) => {}
            }
            if sender.blocking_send(line).is_err() {
                break;
            }
        }
    });
    receiver
}

async fn chat(port: u16) -> Result<(), &'static str> {
    let token = Zeroizing::new(
        std::env::var("NEURA_LOCAL_SESSION_TOKEN")
            .map_err(|_| "A fresh local session credential is required.")?,
    );
    let grant = LocalTextGrant::approve_session_text();
    let mut conversation = LocalConversation::new(port, token, grant.clone())
        .map_err(|_| "The local session could not be created.")?;
    let mut input = input_channel();
    println!("Neura local text prototype. Only text typed here enters this session.");
    println!("/quit, /stop or /clear ends the session. Any input during generation stops it.");
    loop {
        print!("You: ");
        io::stdout()
            .flush()
            .map_err(|_| "Terminal output unavailable.")?;
        let Some(line) = input.recv().await else {
            break;
        };
        let text = line.trim();
        if matches!(text, "/quit" | "/stop" | "/clear") {
            break;
        }
        if text.is_empty() {
            continue;
        }
        let result = tokio::select! {
            biased;
            _ = input.recv() => {
                grant.revoke();
                println!("Session stopped. Restart explicitly to continue.");
                break;
            },
            reply = conversation.reply(text) => reply,
        };
        match result {
            Ok(reply) if grant.is_active() => {
                // Treat generated text as text; never execute tool calls or emit
                // terminal escape sequences supplied by an untrusted model.
                let display: Zeroizing<String> = Zeroizing::new(
                    reply
                        .chars()
                        .filter(|c| !c.is_control() || matches!(c, '\n' | '\t'))
                        .collect(),
                );
                println!("Neura: {}", display.as_str());
            }
            Err(LocalConversationError::InputLimit | LocalConversationError::ContextLimit) => {
                println!("Please send a shorter message for this low-memory session.");
            }
            _ => {
                println!("Local generation unavailable or stopped. No cloud fallback was used.");
                break;
            }
        }
    }
    conversation.stop();
    // The launcher reaps its server on return, including errors and cancellation.
    Ok(())
}

fn main() {
    let result = configuration().and_then(|port| {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .map_err(|_| "The local runtime could not start.")?;
        // Inherited logging settings must never enable HTTP body/header tracing.
        tracing::subscriber::with_default(tracing::subscriber::NoSubscriber::default(), || {
            runtime.block_on(chat(port))
        })
    });
    if let Err(message) = result {
        eprintln!("{message}");
        std::process::exit(1);
    }
}
