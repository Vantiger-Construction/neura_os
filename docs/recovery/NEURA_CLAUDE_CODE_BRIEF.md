# NEURA — Drive `flutter analyze` from 308 errors to 0

## Your job
Take the Neura Flutter app from **308 analyzer errors to 0**, working locally.
Do NOT add features. Do NOT change app behavior. This is repair only.

## Canonical root (the ONLY tree to touch)
```
C:\Users\user1\source\repos\Vantiger-Construction\Neura-O.S\neura\neura_comprehensive_merge\0
```
- Package name is `neuro_companion` (note: NOT `neura_companion` — that misspelling in imports is a bug to fix).
- Sibling forks `..\1 ..\2 ..\3` exist. Fork 1 (~313 errors) and especially fork 2 (7790) and fork 3 (1811) are WORSE. Use them ONLY as a source to copy a missing file FROM. Never switch base to them.

## Hard rules (these are non-negotiable — they encode mistakes already made today)
1. **Measure after every change.** After each fix or small cluster: `flutter analyze > az.txt 2>&1`, then count errors with `Select-String az.txt -Pattern '^\s*error -'`. Record before/after.
2. **The count must go DOWN or stay equal — never up.** If a change raises the count, REVERT it immediately and try a different approach. (Today a fix took 301→351 and a bad quarantine took 314→511. Both were caught by measuring. You must catch them the same way.)
3. **Do NOT quarantine or delete `lib\services\plan`, `lib\services\policy`, `lib\services\neura_action_bus`, or the `replay` / `indexer` / `app_index` / `automation` / `launcher` services.** They are LOAD-BEARING — imported by `main.dart` and the kernel. Removing them surfaces a fresh wave of `undefined_identifier`. Fix them in place.
4. **No guessing at shapes.** Before editing a caller, open the file it depends on and read the ACTUAL class/method/enum. Match callers to the real definition — never invent a signature. (Example already found: `NeuraActionExecutor.execute(BuildContext, String actionId, Map<String,dynamic> args)` returns `Future<bool>`. Callers passing 1 arg / expecting `.ok`/`.data` are written against a dead API and must be updated to the real one.)
5. **Reversible over destructive.** Prefer editing imports/signatures over deleting files. If a file must be set aside, MOVE it to `..\_q_<name>` (outside the project), never delete.
6. **Errors only.** Ignore `info`/`warning` (deprecations, unused imports) until errors hit 0. They don't block a build.

## Strategy — fix from the LEAVES INWARD (this is the efficient path)
The 308 errors are NOT 308 problems. They trace to a small number of missing/drifted **shared root symbols** — one absent enum, registry, or models file throws `undefined_class` / `undefined_identifier` across dozens of importers. Restoring one root clears its whole column at once (restoring `action_executor.dart` earlier cleared 7 importers in one move).

Work this loop:
1. Rank the most-missing symbols:
   - `undefined_class` → `Undefined class '([^']+)'`
   - `undefined_identifier` → `Undefined name '([^']+)'`
   - `uri_does_not_exist` (local, non-`package:`) → the missing file
   - `undefined_enum_constant` → which enum is missing which constant
2. Take the **single most-referenced** root symbol. Find where it's correctly defined — elsewhere in fork 0, or in a sibling fork (`..\1` first, it's healthiest). 
   - If the file exists elsewhere: copy it to the exact path its importers expect (derive the path from the import statement, not from where it sits in the fork).
   - If it's an enum missing constants (e.g. `NeuraCapability` missing `textProcessing`, `systemAutomation`): open the enum, see if callers or a sibling fork show the full intended set, add the missing constants.
   - If callers drifted from a real current API: fix the callers to match the real signature.
3. Re-analyze. Confirm the count dropped. Commit mentally (or `git add -A` per cleared cluster so you can roll back a bad one).
4. Repeat, biggest cluster first, until 0.

## Known specifics already diagnosed (start here)
- **`neura_action_plan_actions.dart`** is structurally truncated (line 1 `expected_executable`) AND written against a dead executor API. It's load-bearing, so don't remove it — reconcile it: fix the top-of-file truncation, update `execute(...)` calls to the real 3-arg signature, and correct the `bool` return handling (it treats `Future<bool>` as an object with `.ok`/`.message`/`.data`).
- **`NeuraCapability`** enum is missing constants (`textProcessing`, `systemAutomation`, likely more). Find the complete set from callers/siblings and restore it — this clears `undefined_enum_constant` across many files.
- **`NeuraPersistentApprovalStore`** shows as `undefined_class` in callers but IS imported by the real `action_executor.dart` — so the definition exists somewhere; find and wire it.
- Duplicate/rival paths exist (`lib\modules\voice\voice_lab_screen.dart` vs `lib\src\modules\voice\...`, `skills\neura_skill.dart` vs `skills\skills\neura_skill.dart`). Pick the one importers expect; fix or remove the stray.

## Dependencies (pubspec)
- Already added and correct: `flutter_secure_storage`, `flutter_tts` (real — drives avatar visemes/lip-sync, keep it).
- `cloud_firestore` / `fl_chart` were only used by a quarantined junk dashboard — do NOT re-add.
- `sqlite3`, `pdf_text`, `pdf_text_extraction`, `txt_docx` are used by offline-doc-search. If those files still error on missing packages and the packages don't resolve, that subsystem may be non-beta — but it's currently in the tree, so first try adding the real packages; only set aside (move, don't delete) if a package genuinely doesn't exist on pub.dev. Measure the tradeoff.

## Firebase note (do NOT act yet — after errors = 0)
`firebase_auth` / `firebase_core` / `firebase_storage` are still in pubspec. The app migrated to Supabase; Firebase C++ native is the suspected Windows cold-start crash. This is the NEXT phase after a clean analyze — flag it, don't touch it during error repair.

## Exit gate
```
flutter analyze   → 0 errors
```
Then STOP and report the final count + a short list of what was fixed per cluster. Do not proceed to Firebase removal, packaging, or any feature work without confirmation.

## Definition of done for THIS brief
- `flutter analyze` reports **0 errors** (info/warnings acceptable).
- No load-bearing subsystem was deleted or quarantined.
- Every reduction was measured; no step left the count higher than it started.
```
