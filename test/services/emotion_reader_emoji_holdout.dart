/// Emoji-bearing messages written BEFORE the reader learned emoji, and never
/// used to tune it. Same label rules as emotionReaderCorpus.
const emotionReaderEmojiHoldout = <(String, Object?)>[
  ('worst day ever 😭', 'sadness'),
  ('miss him so much 💔', 'sadness'),
  ('ugh 😤 my boss again', 'anger'),
  ('exam in an hour 😰😰', 'anxiety'),
  ('WE WON 🥳🎉', 'joy'),
  ('finally home 😴 so done', 'exhaustion'),
  ('nobody showed up to my party 😞', ['loneliness', 'sadness']),
  ('i cant stop laughing 😂😂', 'joy'),
  ('so proud of my little sister 🥹', 'joy'),
  ('i messed up badly 😳 everyone saw', 'shame'),
  ('thanks 👍', null),
  ('what time does the store close? 🤔', null),
  ('pizza tonight 🍕', null),
  ('lol ok 😅', null),
];
