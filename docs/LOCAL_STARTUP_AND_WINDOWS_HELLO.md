# Local startup and Windows Hello

After **Welcome to Neura**, choose **Open my Neura** for your local workspace
or **Continue as guest** for the limited temporary guest activities. Backend
configuration does not require an email account before local use.

An existing owner password still protects the owner path. First-time local
password setup can be skipped with **Continue without an owner password**.
Skipping removes this additional Neura password requirement; an enabled device
lock still applies. Manage the password under **Settings > Privacy & Safety >
Owner password**. Removing an existing password requires that password.

## Set up Windows Hello

1. In the owner-password screen, select **Set up Windows Hello**. Windows opens
   **Settings > Accounts > Sign-in options** on the laptop. Set up a Windows Hello
   PIN and, when supported, face or fingerprint recognition yourself. Neura does
   not receive or store the Windows PIN or biometric data.
2. Return to Neura and select **Check Windows Hello again**.
3. Choose a matching owner passphrase of at least 12 characters, enable
   **Remember me with Windows Hello**, and save. Complete Windows' authentication
   prompt. Cancelling that prompt does not save a remembered login or a new
   owner password.
4. On a later launch, choose **Open my Neura**, then **Use Windows Hello**.
   The owner password remains available if Windows Hello is cancelled or
   unavailable. To revoke remembered access, uncheck the option and unlock with
   the correct owner password.

Without Windows Hello support, password sign-in and optional password skipping
remain available. OS enrollment requires the signed-in Windows user's presence;
it cannot be completed by a remote build or a hosted CI test.

## Optional cloud account

Configured builds retain account sign-in under **Settings > Profile & Account >
Sign in to cloud account (optional)**. Successful sign-in or email verification
returns to the existing Profile screen. Signing out leaves local navigation
available. Account verification and cloud data ownership checks remain separate
from local entry. Local journal data, owner-password records and cloud
credentials are not erased by choosing local use or signing out.

## Verification

Use a separate Windows test account and synthetic data. Record the exact ZIP,
executable hash and packaged checkout before replacing a candidate. A new
extraction folder alone does not isolate per-user storage.

- With configured backend values, verify local setup and a previously unlocked
  owner both open without the account Sign In or Verify Email screen. Repeat
  with backend initialization unavailable.
- Verify the saved skip choice and enabled device lock; retain the existing
  wrong-password and guest-isolation regressions.
- Test optional account sign-in, unverified signup, cancellation and sign-out.
  Back navigation must return to the same local workspace.
- On Windows, check setup settings, enrollment, cancelled and approved OS
  prompts, relaunch, password fallback and revocation. Show/Hide controls must
  preserve the password text and re-mask after lifecycle loss.
- Keep Safe Mode microphone-off and cloud conversation approval explicit.

The State Matrix runs the startup regressions with synthetic backend build
values so an unconfigured test build cannot hide a forced account redirect.
Hosted widget tests do not establish physical Windows Hello enrollment,
microphone behavior or laptop acceptance.
