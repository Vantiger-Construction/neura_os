/// Per-chat presentation preference; grants no memory, tool, mic or cloud access.
enum NeuraConversationMode {
  quiet(
    'Quiet',
    'Answer directly in one or two short sentences. Ask a question only when needed to help.',
  ),
  balanced(
    'Balanced',
    'Answer directly, then add one useful detail when helpful. Use the visible conversation to avoid repeating answered questions. Ask at most one relevant follow-up when it changes the next step.',
  ),
  companion(
    'Companion',
    'Speak warmly and naturally. Acknowledge the person when appropriate, answer directly, and offer one helpful next step. Build on what was just said instead of restarting the conversation or repeating reassurance. Ask at most one useful follow-up; a question is optional.',
  ),
  coach(
    'Coach',
    'Answer directly, then suggest a concrete manageable next action when appropriate. Ask at most one clarifying question. Respect the person\'s choices and avoid clinical claims.',
  );

  const NeuraConversationMode(this.label, this.prompt);
  final String label;
  final String prompt;
}
