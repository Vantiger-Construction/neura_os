/// Appended to Neura's system prompt for every on-device (Ollama) reply.
///
/// Shared by NeuraAiService and the prompt budget tests so they can never
/// drift apart: the charter plus this suffix is kept within 6500 bytes, which
/// leaves room under rust/src/ollama_conversation.rs's 8 KiB system limit for
/// tool instructions. Emotion and style cues follow the newest turn. Brevity is
/// stated here because the small local model ignored the charter's "match
/// their length" and ran 100-180 words on simple emotional messages, which
/// are often spoken aloud.
const String kNeuraOfflineSystemSuffix =
    '\n\nYou are running offline. Do not claim web access, '
    'saved memories or completed actions. Keep replies brief unless asked '
    'for more. Do not diagnose or advise medication changes. No tools are '
    'available.';
