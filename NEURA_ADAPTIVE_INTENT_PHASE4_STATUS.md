# Neura Adaptive Intent OS Phase 4 status

Phase 4 is the opt-in local beta milestone for Neura 1.4.

The permanent validation path must pass on one commit:

1. canonical package-mode Dart formatting;
2. `flutter analyze --fatal-infos`;
3. all Cognitive, Constitution, Intent Compiler, and Adaptive Intent tests;
4. Neura's complete Flutter test suite.

The safety boundary remains unchanged while validation runs: local normalized
signals only, bounded encrypted derived outcomes, direct user gestures, fresh
Action Loom approval, and no message, purchase, money, cloud, calendar, or
unknown-capability executor.
