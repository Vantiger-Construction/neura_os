# Supabase journal-sync deployment — September 18, 2026

## Result
The user's existing project was restored to ACTIVE_HEALTHY on its existing Free plan. No new project or paid tier was created. This deploys journal sync and verifies the existing email Auth settings; payment verification and Stripe settings were not changed.

Source application: merge commit `567f49c59b1bc78ec46653503d4ec10a3aa69baa` (PR #87).

## Migration history
Supabase assigned live migration versions at deployment. The SQL of the three journal migrations is unchanged; this change renames the repository files and updates the test references to match that history.

| Original source version | Deployed version | Migration |
|---|---|---|
| 20260909000000 | 20260918181707 | create_journal_entries |
| 20260911000000 | 20260918181725 | track_journal_revision_time |
| 20260918000000 | 20260918181743 | compare_journal_revisions |
| New project hardening | 20260918181858 | restrict_rls_auto_enable_execution |

The final migration revokes PUBLIC/anon/authenticated execution of the administrative RLS event-trigger helper while retaining the enabled event trigger. Its repository version guards the same revocation when that Supabase-managed helper does not exist, allowing local/self-hosted schema tests and fresh installations to proceed.

Do not mix the old timestamps with these deployed timestamps when running future CLI pushes. For another environment that previously applied the old source versions, inspect its migration list and reconcile the identical migrations before deployment; do not blindly replay or force migration history.

## Observed verification
- Live Postgres transactional QA passed: insertion, owner binding despite a spoofed payload owner, server updated_at on edits, stale revision rejection, insert-conflict protection, idempotence, RLS ownership-transfer denial, cross-user read/RPC isolation, missing-identity denial and anonymous denial.
- All synthetic identities and journal rows were rolled back. The live journal table had zero rows afterward.
- The sync function is SECURITY INVOKER; RLS is enabled with own-row SELECT/INSERT/UPDATE/DELETE policies.
- Live HTTP checks passed: Auth settings reachable, email authentication and signup enabled, email confirmation required; anonymous journal GET and RPC POST rejected with HTTP 401 / PostgreSQL 42501.
- Supabase security advisors returned no findings after the helper privilege correction.
- Prior source-head validation: State Matrix, Local Runner and Android packaging passed; Local Runner included clean fatal analyzer checks, 456 Flutter tests and a Windows release build.

The reusable SQL QA is `tools/sync_tests/verify_live_journal_revision.sql`. It creates synthetic identities only inside a transaction and ends with ROLLBACK. Run it in an authenticated administrative database session; do not replace rollback with commit. It tests SQL/RLS behavior, not email delivery or device behavior.

## Remaining device gate
Physical Windows/Android QA is NOT RUN. This execution environment has no accessible Windows session, Android device, ADB endpoint or USB bus. Existing CI builds omit project defines, so configured test builds must be produced with the external public configuration supplied for this project.

Required observations remain: confirmed-email login on both devices; two-way journal round trips and conflicting offline edits; edit/delete during upload; restart recovery; Safe Mode microphone-off/no-cloud; local-only voice and interruption; fresh approval for every provider request and action; retained private-file/memory restrictions; local API approval and revocation.

No application safety or approval logic was changed by the deployment. Backend tests are not physical-device acceptance or release sign-off.
