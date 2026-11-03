# Neura repository instructions

Read and follow the root `AGENTS.md` before making changes. Use current source,
lockfiles and CI definitions as evidence; historical PR descriptions and reports
are not proof that the checked-out revision passes.

Neura is a local-first wellness companion. Preserve exact-request cloud approval,
Safe Mode microphone-off, cancellation and foreground ownership, explicit memory
consent, encrypted storage, local journaling and bounded offline operation.
Never use real private data as test fixtures or weaken security/test gates.

Use the branch's pinned Flutter/Rust versions and locked dependencies. Run checks
appropriate to the changed paths and report exact results and unavailable
platforms. Prefer focused PRs; do not treat agent completion as merge, deployment
or release approval.

Specialist profiles and example tasks are documented in `docs/GITHUB_AGENTS.md`.
