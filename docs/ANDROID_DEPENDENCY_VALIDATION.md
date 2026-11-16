# Android dependency review and acceptance

This validation supports PR #220 without granting merge or release approval.
It retains the five buildscript constraints and Gradle 9.9.1 proposed by that
PR. Application runtime dependencies, signing configuration, permissions and
encrypted-memory formats are not changed by this validation work.

## Automated evidence

`Android dependency validation` and `Android startup voice safety` run on
ephemeral hosted Linux runners with `contents: read`, no release credentials,
and no installation or release publishing. They also accept stacked reviews
targeting `dependabot/gradle/android/**`. A draft stacked PR can therefore
validate changes against #220 without invoking the separate maintainer package
delivery workflows targeting `Neura`. Keep merging and release changes on hold.

The dependency lane records the exact candidate commit/tree and finds its
baseline with `git merge-base HEAD refs/remotes/origin/Neura`. Baseline and
candidate use Flutter 3.47.9 and JDK 17, separate Gradle user homes and the
committed lockfile. Each must compile an actual debug APK. The Gradle init
script records both app runtime variants, every root/project buildscript
classpath, the Flutter included build's own buildscript and JVM tool classpaths,
and Gradle distribution JAR metadata. Missing included builds, unresolved
dependencies or partial inventories fail validation.

The comparison requires identical debug/release runtime modules and project
components, confirms running Gradle 9.9.1 and unchanged AGP/Kotlin selections,
exercises all five updated tooling constraints and rejects mixed
`bcpkix`, `bcprov` and `bcutil` versions. It does not force a different version
or alter resolution. Unexpected differences require review, not suppression.

The OSV API receives only public Maven coordinates and versions. Requests,
responses, input hashes and advisory matches are retained. Candidate findings
and incomplete/error/pagination results fail the lane. Baseline findings are
retained as findings rather than passed off as clean. Gradle core is queried by
distribution version. Distribution JARs without Maven metadata are listed as
unmapped; this is not a complete advisory-free claim for every bundled library.
No severity, reachability or advisory exclusions are applied.

Both debug APKs must pass Android Build Tools signature verification. Receipts
record certificate fingerprints, archive hashes, source and configuration
hashes, application ID, minimum/target SDKs, permissions and native ABIs. The
comparison rejects permission, SDK, app-ID or ABI changes. Both builds use one
ephemeral runner's debug key and deliberately increasing synthetic build
numbers. Passing `tools/release/check_android_update.py` for that pair proves
only a static synthetic signer/version preflight. It proves neither an Android
installation nor compatibility with an existing user's APK.

Candidate release compilation and Android lint run separately from the OSV
finding result. Release compilation does not configure a production signer,
publish an APK, or establish that a production release can be installed. Logs
and JSON evidence are retained for 14 days, including failures. The dependency
artifact omits APKs; the startup workflow retains its debug test APK.

## Compatibility review

AGP 9.5 requires Gradle 9.6 or later and JDK 17. Flutter 3.47 supports enabled
built-in Kotlin. KGP 2.4.21's published fully supported ranges end at Gradle
9.7.0 and AGP 9.3.1; the previous Gradle 9.8.2/AGP 9.5.1 baseline already
exceeded them. Successful builds add practical evidence, not a claim of full
upstream support. Keep the existing `flutter_tts` and `home_widget` migrations
and their source-hash checks intact. Inspect Guava's disclosed `StandardValues`
final-method regression and Bouncy Castle's stricter certificate/parsing rules
when examining task or signing failures.

Sources: [AGP 9.5](https://developer.android.com/build/releases/agp-9-5-0-release-notes),
[KGP compatibility](https://kotlinlang.org/docs/gradle-configure-project.html),
[Flutter built-in Kotlin](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin),
[Gradle 9.9.1 security fixes](https://docs.gradle.org/9.9.1/release-notes.html),
[Guava 33.8.0](https://github.com/google/guava/releases/tag/v33.8.0),
[Bouncy Castle 1.87](https://github.com/bcgit/bc-java/blob/r1rv87/docs/releasenotes.md).

## Required installation and Samsung evidence

These checkpoints remain **UNVERIFIED** until evidence is attached. Synthetic
tests, a signed APK, and hosted compilation cannot complete them.

| Checkpoint | Required evidence |
| --- | --- |
| Existing installation | Exact installed APK identity, version code and signer certificate; compare with the proposed candidate using the offline checker before attempting an update. |
| Same-signer upgrade | An isolated test installation with synthetic journal, preferences and encrypted memories; increasing version code and unchanged signer; retained records decrypt after update and restart. |
| Samsung startup | SM-S366V / Android 16 cold-start result, APK SHA-256, signer, source commit, observation and crash log if startup closes or stays blank. |
| Permissions and speech | Deny/revoke microphone permission, verify opt-in and greeting order, exercise local recognition and speech, interruptions and ten-minute conversation. |
| Lifecycle restrictions | Verify real microphone shutdown on stop, background, Safe Mode and recovery; no automatic cloud fallback or background cloud voice. |

Use synthetic data for upgrade and recovery tests. Never uninstall, clear app
data, replace a signer or wipe real encrypted memories to make an installation
appear successful. A signer/version mismatch is a blocker requiring a separate
preservation plan. Record failed and unavailable results alongside passes.
