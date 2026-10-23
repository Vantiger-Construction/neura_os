# Evidence checkpoint — October 23, 2026

## Repository and hosted Windows evidence

- Default branch inspected at `dd6a53f7bc25f751a48e23087e5040c95125a588`,
  merged [PR #144](https://github.com/Vantiger-Construction/neura_os/pull/144).
  GitHub records the merge on October 23 at 03:12 UTC (October 22 at 10:12 PM
  America/Chicago). The earlier SAPI implementation, PR #139, is also merged.
- [Windows local speech safety run 39868591948](https://github.com/Vantiger-Construction/neura_os/actions/runs/39868591948),
  PR head `125d278e5d7bc8a442f22c6b5050adf0b74414d6`, completed successfully.
  Its job `120136997770` and execution log were inspected directly: three real
  CMake filter cases; locked dependency restore and targeted analysis;
  **73 selected Dart tests**; actual owner MSVC 19.51 compilation/linking with
  genuine Flutter libraries and production exception settings; native
  ownership/escaping test; complete release application compilation; and the
  check rejecting a bundled `flutter_tts_plugin.dll` all passed. This is the
  PR head's CI result, not a new post-merge device result. No audio was executed.
- Current CMake compiles only the build-local filtered registrant and includes
  the filtered plugin list, while preserving other plugins/FFI dependencies.
  Unrecognized legacy registration/build formats fail configuration.
- The native primary window owns the SAPI channel, purges on background/close
  and releases it before the Flutter messenger. Speech uses installed Microsoft
  desktop voices and has no legacy fallback. Startup greeting remains false.
- Existing fixed-text harness and acceptance procedure were reused. No new
  speech engine, microphone path or application runtime change was introduced.

## New local helper verification (Linux, synthetic only)

PowerShell 7.4.7 helper assertions: **41 passed** at preparation. They exercise
file/identity inspection, redaction and simulated input, with no Windows app
execution. The original CMake fixtures were rerun: **3 passed**. The original
native ownership/escaping executable was compiled with g++ C++17 and strict
warnings: **17 assertions passed**, with no COM voice or audio. Genuine Windows
PowerShell 5.1 execution of the new helper remains pending its PR workflow.

## Actual physical Windows results

| Scenario | Debug production | Release production | Debug harness | Release harness |
| --- | --- | --- | --- | --- |
| Cold startup / first audible speech | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| Repeated audible completion | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| Stop / replacement | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| Safe Mode and microphone stays off | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| Background / shutdown | NOT RUN | NOT RUN | NOT RUN | NOT RUN |
| Chat replies / preview / normal mascot | NOT RUN | NOT RUN | Not applicable | Not applicable |
| Matching local bundle / diagnostics / symbols | NOT RUN | NOT RUN | NOT RUN | NOT RUN |

No authorized interactive physical Windows connection was available in this
session. A CI runner's existence does not supply acoustic or device acceptance.
No local PC observations, installed EXE hash, new dump or source-line diagnosis
has been invented. The downloaded helper is for collecting those results.

## Historical crash interpretation

The [August debugger report](https://github.com/Vantiger-Construction/neura_os/issues/32#issuecomment-5318685604)
reports `0xC0000005` at `flutter_tts_plugin+0xe657`, including reproduction with
mascot creation disabled. It supersedes the original mascot-startup hypothesis.
Its original dumps/binaries/symbols were not available for independent analysis.
The precise native source-line cause remains unproved. PR #144 removes the
historical plugin load path; it does not certify acoustic behavior or repair
that old upstream binary. [Issue #32](https://github.com/Vantiger-Construction/neura_os/issues/32)
must remain open for reviewed physical evidence. Startup greetings stay off.
