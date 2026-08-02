# Recommended Neura upgrade order

## 1. Recovery and reproducibility
- Establish one canonical source tree.
- Generate a SHA-256 manifest for every release.
- Keep source, generated builds, installers, and user data in separate folders.
- Add a restore test before declaring a backup complete.

## 2. Runtime reliability
- One supervisor starts the API, AI runtime, Unity shell, and dashboard.
- Every service exposes `/health`, `/ready`, and version information.
- Use append-only structured logs and automatic crash snapshots.
- Add Safe Boot that disables nonessential modules after repeated crashes.

## 3. Contract-first architecture
- Freeze versioned event and action schemas.
- Route all modules through a single API gateway.
- Keep Unity as the presentation/presence layer and core policy/storage outside it.
- Add backward-compatible `/v1`, `/v2`, and `/v3` routes.

## 4. Privacy and safety
- Encrypt local memory and exports.
- Make cloud sync opt-in.
- Require explicit approval before external actions or financial operations.
- Separate wellness guidance from diagnosis or emergency services.

## 5. Product experience
- A real dashboard with service health, recent activity, goals, rituals, and alerts.
- A settings page that controls persona, privacy, models, notifications, and hardware mode.
- First-run onboarding with a hardware test and offline-first default.
- Graceful fallback when Unity, cloud AI, or optional modules are unavailable.

## 6. Release engineering
- Signed Windows installer and uninstall support.
- Staged auto-update with rollback.
- Automated smoke tests after installation.
- Android build pipeline only after the Windows reference flow passes end-to-end.
