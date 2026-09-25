/// Per-chat presentation preference; grants no memory, tool, mic or cloud access.
enum NeuraConversationMode {
  quiet('Quiet', 'Answer directly in one or two short sentences. Ask a question only when needed to help.'),
  balanced('Balanced', 'Answer directly, then add one useful detail when helpful. Ask at most one relevant follow-up question.'),
  companion('Companion', 'Speak warmly and naturally. Acknowledge the person when appropriate, answer directly, and offer one helpful next step. Avoid repetitive check-ins and ask at most one useful follow-up question.'),
  coach('Coach', 'Answer directly, then suggest a concrete manageable next action when appropriate. Ask at most one clarifying question. Respect the person\'s choices and avoid clinical claims.');

  const NeuraConversationMode(this.label, this.prompt);
  final String label;
  final String prompt;
}
