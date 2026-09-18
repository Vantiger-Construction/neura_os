# Supabase continuity setup

Neura uses Supabase only as an optional cloud backend. Local journaling and
existing Windows premium unlocks continue to work when Supabase is absent.
Safe Mode must continue to skip every cloud initialization and sync attempt.

## Services

- Supabase Auth: email/password registration, verification, reset, and profile.
- Postgres: optional two-way sync of `journal_entries`, protected by row-level
  security so authenticated users can access only their own rows.
- Edge Function: stateless Stripe Checkout verification. Stripe remains the
  payment source of truth; no payment secret belongs in the app or repository.

## Link the selected continuity project

The user selected the existing project for deployment on September 18, 2026. See [deployment evidence](SUPABASE_DEPLOYMENT_20260918.md). Keep public build values outside the repository.

1. Select the existing Free project in the user's organization.
2. Link it from an authenticated Supabase CLI session:
   `supabase link --project-ref <project-ref>`
3. Apply the committed schema:
   `supabase db push`
4. Configure the purchase verifier's server-side secret directly in Supabase.
   Never place its value in a shell transcript, Dart define, GitHub file, or
   client build.
5. Deploy the function:
   `supabase functions deploy verify-purchase --no-verify-jwt`
6. Enable email/password Auth. Keep email confirmation enabled.
7. Add the deployed function URL as the Stripe Payment Link completion redirect.

## Build configuration

Supply only public client configuration at build time:

```text
SUPABASE_URL
SUPABASE_ANON_KEY
VERIFY_PURCHASE_URL
```

Example:

```bash
flutter build windows --release \
  --dart-define=SUPABASE_URL=<project-url> \
  --dart-define=SUPABASE_ANON_KEY=<publishable-key> \
  --dart-define=VERIFY_PURCHASE_URL=<function-url>
```

Repeat the same defines for Android builds. These are endpoint/public client
values, not server secrets. Do not add them to source files.

## Validation

1. Build without defines: Neura boots local-only and never shows cloud sign-in.
2. Enter Safe Mode with defines present: Supabase remains offline.
3. Sign up and verify one test user; another user's journal rows must be
   unreadable and unwritable.
4. Create, edit, and sync a journal entry on two test installations.
5. Verify an unpaid/test-invalid Checkout Session is rejected.
6. Verify a paid Stripe test Checkout Session unlocks premium locally.
7. Disable the project temporarily: startup and local journaling still work;
   new redemption and sync fail closed without revoking an existing unlock.

## Provider-neutral exit

The app already calls purchase verification through `VERIFY_PURCHASE_URL`
over HTTPS rather than through the Supabase SDK. A future Neura-owned service
can replace that endpoint without changing the Windows client. Auth and journal
sync should remain behind their existing service classes; future providers must
preserve the same local-only, Safe Mode, wipe, ownership, and conflict-resolution
semantics.
