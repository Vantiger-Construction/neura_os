# Neura Adaptive Intent OS 1.4 validation notes

The checked-in Dart sources are formatted in package mode after
`flutter pub get`, matching the permanent hosted validation order.

The release gate for this research branch is:

1. canonical package-mode Dart formatting;
2. `flutter analyze --fatal-infos`;
3. all Cognitive, Constitution, Intent Compiler, and Adaptive Intent tests;
4. Neura's complete Flutter test suite.

The package remains draft until all four gates pass on the same branch head.
The active-session UI remains local and proposal-only; it does not execute
messages, purchases, calendar changes, cloud requests, or Action Loom actions.
