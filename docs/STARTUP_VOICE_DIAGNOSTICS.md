# Startup voice device diagnostics

Use the [non-destructive diagnostic kit](../tools/startup_voice_diagnostics/README.md)
with the [startup acceptance contract](STARTUP_VOICE.md).

It pins the original PR #161 and newer merged #177 packages, checks release bytes
and APK identities without installing them, inventories Windows desktop SAPI
prerequisites without activating speech, and collects bounded Android startup
markers and microphone metadata without exporting raw logs.

Use an empty Android AVD and a separate Windows test account. Existing Android
encrypted-data upgrades remain blocked: the current 11.2.0 secure-storage lock
and documented staged migration have not established a safe existing-key path.
Disposable debug certificate differences are an additional update blocker.
Do not uninstall, clear or overwrite an existing valuable installation.

Physical observations are recorded independently as PASS, FAIL, BLOCKED or
NOT RUN. Neither the kit's static checks, mocked tests nor package CI is a
Windows laptop or Samsung SM-S366V hardware acceptance result.
