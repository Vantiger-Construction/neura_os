# Automated evidence — November 6, 2026

No physical Windows or Samsung session was available. No app was installed,
launched, granted microphone access, reset or wiped. No real audio, transcript,
journal, encrypted store or credential was read. Device records are templates.

## Inspected source and package identity

| Item | Recorded identity |
| --- | --- |
| Default branch snapshot | `6523cbe50490613dbb68b2a4d35cfa704efc2fd2` |
| Default tree | `e265bb295afa3480bdc9e97501a5d6ba1655366f` |
| PR #161 merged commit | `6aa37404e81fd2ee33d160997c78e5045bae0b55` |
| PR #161 packaged source / tree | `e8d99229321a025d2c3f3a2ab173e489b1343195` / `c4c234dbe15711d28e0d6c21933d31cea14e969d` |
| PR #177 packaged source / tree | `a4796a3a637a254a71f8dcf0b6eae96f521f0c70` / `e265bb295afa3480bdc9e97501a5d6ba1655366f` |

All twelve public release assets (two platforms, two revisions, three assets
each) were independently downloaded. Every byte length and SHA-256 matched
GitHub's release metadata. The four platform build manifests and checksum lists
matched their recorded sources, PR heads, run IDs, attempts and release tags.
All four archives were traversed without extraction/execution; every member was
CRC-checked and hashed. Both Windows ZIPs contain 56 members and valid x64 PE /
Flutter release payloads, with no `flutter_tts_plugin.dll`. Both APKs contain
2,177 members. Per-file Windows hashes are in `automated/*-package.json`.

| Binary | Bytes | Independently verified SHA-256 |
| --- | ---: | --- |
| PR #161 Android | 259884409 | `dbf1a2ea2d0cfed0e768cbd77650bd51493585fa88f384324fc7c1a3e40644b8` |
| PR #161 Windows | 82208363 | `3f15b979db4bf64933a0641c41266a03b1277ce3e0a13663e508de532b2eaf2d` |
| PR #177 Android | 259954097 | `1ea4596be763db404314d92311838cb1373dca9d15e11e370bc430a2362d0e0a` |
| PR #177 Windows | 82263807 | `5c913fe232b32792df597fe11c9cef701afb9d2de1805099bf3e3029ca16e62e` |

Google's Build-Tools 36.0.0 `apksigner` independently verified both APKs' v2
signatures. `aapt dump badging` confirmed `com.neurocompanion.app`, version 1.5.1,
version codes 596 / 607 respectively, minimum API 24, target API 36, compile API
37 and declared RECORD_AUDIO. Startup recognition itself still requires API 31+
and available local services. Google repository metadata verified the build-tools
archive length 63737259 and its published SHA-1
`b0b6376977657e8ad9b969bacf4093601da2c6fb` before the tools were used.

| APK | Signer certificate SHA-256 |
| --- | --- |
| #161 | `4827f8ec9f68b78abd93c1c65b38d8561788f676f09d5f9347fc9c79256e58e8` |
| #177 | `9c2411521831f716212528aa8060c3ecd32a105398f4990ac2d02669488593fb` |

**The signatures differ.** These APKs must not be used as interchangeable updates
to a valued installation. The independent encryption migration gate also remains
BLOCKED even if an existing installation happens to have the same signer.

## Source configuration review

The default tree matches the newer #177 package tree. Comparison from #161's
packaged source found unchanged native local input owners, local speech input
service, startup opt-in preferences and TTS service. Chat changes add the selected
face; startup also initializes its saved avatar preference. This is a source
comparison, not a new hardware speech result.

Inspected safeguards include owned Microsoft `MS-…-DESK` SAPI input and
`TTS_MS_…` voices; Android `isOnDeviceRecognitionAvailable` /
`createOnDeviceSpeechRecognizer`; native Android onPause shutdown; foreground,
session invalidation, Stop, Safe Mode, recovery and wipe barriers; required actual
greeting completion; Android installed voices excluding network-required and
not-installed output. Existing diagnostic tools include the Windows speech
evidence helper, fixed-text TTS harness, native lifecycle harness and synthetic
startup, input, preference, settings, cloud and wipe regressions. The separate
experimental Windows ONNX ASR contract is not the startup SAPI path.

Both manifests say `configuration: configured` and `device_qa: pending`.
Configured Supabase backend traffic must be distinguished from a model request;
startup voice consent does not authorize either private-memory access or an AI
request. The kit adds no provider configuration or traffic interception.

The #161 package lockfile pins secure storage 10.3.1; #177/default pins 11.2.0.
The current dependency notes still describe a 10.3.1 migration stage and require
on-device preservation of older keys. Neither package validation establishes that
an older store has completed migration. `resetOnError: false`, `migrateOnAlgorithmChange: true` and
`migrateWithBackup: true` remain in application source. No validated upgrade path
or key recovery result was found in the inspected evidence; existing-data installs
remain BLOCKED. No product dependency or encryption behavior was changed here.

## Check results and limits

| Check | Status | Scope |
| --- | --- | --- |
| PR #161 head `d6edfbc90bc619da7c8d2df8a6bfeeb2292949ab` check-runs API | PASS | 39 successful, 4 skipped, 43 returned; historical exact-head CI, not rerun |
| PR #177 head `9fd4011c47cbd1c5e624205ff0060589ba275924` check-runs API | PASS | 39 successful, 4 skipped, 43 returned; historical exact-head CI, not rerun |
| #161 Windows run 41944653817 and Android run 41944653809 | PASS | GitHub reports compilation and download-verified delivery success |
| All twelve downloaded release assets | PASS | Independent local lengths/hashes; four manifest/checksum/archive verifications |
| Both APK signatures/application identities | PASS | Independent local SDK tool execution; no device installation |
| New diagnostic helper regressions | PASS | 19 synthetic tests on Linux, Python 3.12; no device/network/audio |
| Existing source-composition regressions | PASS | 17 synthetic tests on Linux |
| Existing Windows evidence helper fixtures | PASS | 44 synthetic assertions under PowerShell 7.5.4 on Linux; no Windows audio |
| Existing portable TTS ownership/escaping harness | PASS | 21 assertions compiled with g++ C++17; does not compile Windows SAPI |
| New PowerShell collector syntax | PASS | PowerShell 7.5.4 parser on Linux; no SAPI invocation |
| Workflow YAML / read-only permission / full Action pins | PASS | Locally parsed; new hosted Windows/Linux jobs require their own CI results |
| Existing Windows plugin-filter tests | BLOCKED | Three tests could not start because this environment lacks CMake; not a demonstrated code failure |
| Full Flutter/native Windows/Android build rerun | BLOCKED | Matching Flutter/platform build tools absent from this Linux environment |
| New Windows collector SAPI execution / PowerShell 5.1 | NOT RUN | Requires Windows; hosted parser validation was added but is not yet a result |
| Empty AVD installation and UI | NOT RUN | No Android device/emulator was attached |
| Physical Windows laptop acceptance | NOT RUN | No supervised hardware/audio/mic observations |
| Physical Samsung SM-S366V / Android 16 acceptance | NOT RUN | No verified newer installation or physical observations |
| Installing over existing valuable Android data | BLOCKED | Unvalidated key migration and disposable-signing concerns |
| Connected cancellation/no-cloud-dispatch observations | NOT RUN | Requires supervised exact-request UI and independently scoped dispatch evidence |

The kit's workflow tests helpers on Ubuntu/Windows and parses the collector with
Windows PowerShell 5.1. No device is attached and no voice/mic is opened in that
workflow. A successful workflow would still not be hardware acceptance.

## Source references

- [PR #161](https://github.com/Vantiger-Construction/neura_os/pull/161)
- [PR #161 release](https://github.com/Vantiger-Construction/neura_os/releases/tag/neura-ci-pr-161-d6edfbc90bc6-e8d99229321a)
- [PR #177 release](https://github.com/Vantiger-Construction/neura_os/releases/tag/neura-ci-pr-177-9fd4011c47cb-a4796a3a637a)
- [Windows delivery run](https://github.com/Vantiger-Construction/neura_os/actions/runs/41944653817)
- [Android delivery run](https://github.com/Vantiger-Construction/neura_os/actions/runs/41944653809)
- [Pinned source](https://github.com/Vantiger-Construction/neura_os/tree/6523cbe50490613dbb68b2a4d35cfa704efc2fd2)
- [Google build-tools metadata](https://dl.google.com/android/repository/repository2-1.xml)

See `automated/` for machine-readable package and CI snapshots; `device-templates/`
and `evidence-template.csv` contain no completed hardware observations.
