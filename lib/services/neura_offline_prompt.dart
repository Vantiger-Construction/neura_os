/// Appended to Neura's system prompt for every on-device (Ollama) reply.
///
/// Shared by NeuraAiService and the prompt budget tests so they can never
/// drift apart: rust/src/ollama_conversation.rs rejects a system prompt over
/// 6500 bytes. Brevity is stated here because the small local model ignored
/// the charter's "match their length" and ran 100-180 words on simple
/// emotional messages, which are often spoken aloud and capped at 256 tokens.
const String kNeuraOfflineSystemSuffix =
    '\n\nYou are running offline. Do not claim web access, '
    'saved memories or completed actions. Keep replies brief unless asked '
    'for more. Do not diagnose or advise medication changes. No tools are '
    'available.';
