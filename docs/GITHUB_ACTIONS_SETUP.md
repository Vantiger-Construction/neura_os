# GitHub Actions setup

`Neura Actions validation` runs on relevant pull requests, pushes to `Neura`,
and manual dispatch. It checks every workflow with checksum-pinned
[actionlint 1.7.12](https://github.com/rhysd/actionlint/releases/tag/v1.7.12)
and runs source-composition regression tests on Linux and Windows. It uses
read-only repository permissions, cancels superseded validation, and needs
no custom secrets or local runner. `.github/actionlint.yaml` declares the
existing `neura` runner label; unknown labels still fail validation.

The avatar conversation workflow composes exact reviewed commits, verifies
the live SAPI head and the merged motion commit's ancestry, and preserves
failure diagnostics. Application, test and lockfile merge conflicts fail.
Conflicts in the conversation and Windows speech workflow definitions retain
the source PR's definitions inside disposable composition. The complete combined test
suite and native Windows build remain required.

To run checks manually, open Actions, select **Neura Actions validation**,
choose **Run workflow**, and select the branch. Run **Neura avatar conversation
integration** for the full composed Flutter/native/build validation.

The repository's existing Windows runner uses the labels `self-hosted`,
`Windows`, `X64`, and `neura`. Local packaging and retained-toolchain checks
still use it. They can queue while it is busy or offline. Keep the runner
service running and inspect its current job before retrying queued work.
Hosted checks do not establish microphone, audio playback or device acceptance.

Repository settings were inspected on November 2, 2026: Actions was enabled,
default token permissions were read-only, and all external contributors
required approval. These settings were preserved. GitHub also displayed a
billing warning; billing changes must be handled by the account owner.
