# On-device voice evaluation and metadata boundary

## Provider-neutral engines

Chat and voice journaling can now observe a common `NeuraSpeechEngine`
contract. Adapters are provided for:

- Windows WinRT continuous recognition;
- the existing `speech_to_text` platform path; and
- an experimental ONNX int4 native channel.

The existing WinRT and `speech_to_text` paths are marked platform-managed, not
verified on-device: Windows dictation can depend on the online speech setting,
Android's standard recognizer may stream audio to remote servers, and Apple
requires a native on-device-only request flag. The strict engine registry and
benchmark reject both adapters. This is an intentional correction to the
architecture boundary, not a claim that current production recognition is
offline.

The Windows runner now contains a prototype implementation of
`neura/on_device_asr` using the Sherpa-ONNX streaming C API and PortAudio. It
supports only the seam's `isAvailable`, `start`, `stop`, and `onSegment`
contract. The Android runner remains unimplemented. No model binary, runtime
DLL, dependency download, license acceptance, or claimed accuracy is hidden in
this change. Production selection continues to use the existing engines.

## Explicit Windows prototype setup

The prototype has two independent gates and both default off:

1. Configure the Windows build with
   `NEURA_ENABLE_WINDOWS_ON_DEVICE_ASR=ON` and point the four CMake cache
   entries `NEURA_SHERPA_ONNX_INCLUDE_DIR`, `NEURA_SHERPA_ONNX_LIBRARY`,
   `NEURA_PORTAUDIO_INCLUDE_DIR`, and `NEURA_PORTAUDIO_LIBRARY` at SDK files
   already present on the developer machine. The build does not fetch or copy
   those SDKs or their runtime DLLs.
2. At runtime, set `NEURA_ON_DEVICE_ASR_ENABLE=1` and set
   `NEURA_ON_DEVICE_ASR_MODEL_DIR` to an existing absolute local directory.
   Choose the explicit model profile below. Neura never downloads, relocates,
   or modifies model files.

The practical reference profile is `zipformer-en-2023-06-26-int8`, using the
English streaming model documented by
[Sherpa-ONNX](https://k2-fsa.github.io/sherpa/onnx/pretrained_models/online-transducer/zipformer-transducer-models.html).
After independently obtaining and verifying a trusted model and its license,
place these existing files together in a plain local directory:

| Component | Filename |
| --- | --- |
| Encoder | `encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx` |
| Decoder | `decoder-epoch-99-avg-1-chunk-16-left-128.onnx` |
| Joiner | `joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx` |
| Tokens | `tokens.txt` |

```powershell
$env:NEURA_ON_DEVICE_ASR_ENABLE = '1'
$env:NEURA_ON_DEVICE_ASR_MODEL_DIR = 'D:\NeuraModels\zipformer-en'
$env:NEURA_ON_DEVICE_ASR_MODEL_PROFILE = 'zipformer-en-2023-06-26-int8'
```

The default/`int4` profile retains the original `encoder.int4.onnx`,
`decoder.int4.onnx`, `joiner.int4.onnx`, and `tokens.txt` contract. It is only
a candidate convention; an int4 model has not been validated. The historical
Dart class and `onnx_int4_experimental` identifier are retained for seam
compatibility, not as evidence of model precision. Record the actual profile
and file hashes alongside benchmark metrics. Unknown profiles fail closed.

Reference SDK headers checked: Sherpa-ONNX `v1.12.14` C API and PortAudio
`v19.7.0`. Use matching headers/libraries/DLLs of one architecture, including
the ONNX Runtime required by that Sherpa build. Supply runtime DLLs next to the
evaluation executable yourself; an explicitly enabled build needs them even
with runtime capture disabled. Use trusted self-contained ONNX models: this
prototype is not a sandbox for untrusted model graphs or DLLs.

For example, after a normal `flutter build windows --debug` has generated the
Windows build, reconfigure that **evaluation build** with your existing SDKs:

```powershell
cmake -S windows -B build/windows/x64 `
  -DNEURA_ENABLE_WINDOWS_ON_DEVICE_ASR=ON `
  -DNEURA_SHERPA_ONNX_INCLUDE_DIR=D:/AsrSdk/sherpa/include `
  -DNEURA_SHERPA_ONNX_LIBRARY=D:/AsrSdk/sherpa/lib/sherpa-onnx-c-api.lib `
  -DNEURA_PORTAUDIO_INCLUDE_DIR=D:/AsrSdk/portaudio/include `
  -DNEURA_PORTAUDIO_LIBRARY=D:/AsrSdk/portaudio/lib/portaudio.lib
cmake --build build/windows/x64 --config Debug
```

This enables the native channel, not production engine selection. A deliberate
developer benchmark must construct `NeuraOnnxInt4SpeechEngine` and invoke
`NeuraSpeechBenchmarkHarness.run`; ordinary chat/journal microphone routing is
unchanged. Do not log `segments` or the return from `stop`. Always dispose the
engine in a `finally` block. No startup/background capture is installed.

`isAvailable` returns true only when the backend was explicitly compiled, the
runtime opt-in is exactly `1`, all four model files resolve inside that local
directory, the path is not a URL, UNC path, remote drive, reparse point, or
offline/cloud placeholder, the model loads,
and a 16 kHz mono microphone stream is supported. The Dart engine remains
`experimental`, so even an available backend is excluded from ordinary engine
selection unless the caller explicitly includes experimental engines. The
first prototype emits partial/final text but deliberately does not invent
confidence or pause values that its transducer does not provide.

The audio callback only copies into a fixed two-second buffer. One decoder
worker owns feature extraction, decoding, endpoint reset, and results. Buffer
overflow ends capture and discards the incomplete stop transcript. UI segments
and the per-session transcript are also bounded. Safe Mode/disposal sends
`stop` with `discard: true`: capture closes, pending decoding is cancelled,
the worker joins, and queued text is cleared. A currently executing inference
must return before the join can finish; a hung third-party DLL is not covered
by this in-process prototype. Ordinary stop alone flushes the bounded tail.

## Automated evidence and remaining acceptance

`tools/Test-NeuraWindowsOnDeviceAsrContract.ps1` checks the default-off source
contract. Add `-RunNativeHarness` to compile and execute the shared production
session with fake audio/decoding. `Neura-FastCheck.ps1 -BuildWindows` now runs
that executable using the existing CMake/C++ toolchain. It downloads nothing,
opens no microphone, and deletes its small generated build directory afterward.

The same standalone harness can run without Flutter on Linux/Windows:

```text
cmake -S tools/asr_harness -B build/asr-harness
cmake --build build/asr-harness --config Release
ctest --test-dir build/asr-harness -C Release --output-on-failure
```

Ten executable checks cover buffer bounds/order, stream/open/start failures,
partial/final delivery, restart, synchronous cancellation during active decode,
overflow, exception/disposal cleanup, and discarding the stop transcript.
On Linux the harness denies socket creation before running any worker, and
asserts that the denial is active. These checks test the real session code with
fake device/decoder endpoints; they do not prove SDK or microphone behavior.

Local evidence for this revision (2026-09-27):

- All ten native checks passed in optimized and AddressSanitizer/UBSan builds
  with network sockets denied. LeakSanitizer was disabled because this executor
  cannot inspect its process tasks; no leak-sanitizer result is claimed.
- Default-off and enabled C++20 translation units passed strict syntax checks
  against the real reference Sherpa/PortAudio headers and narrow Windows/Flutter
  declaration stubs. This is not an MSVC build or DLL linkage result.
- Eighteen Dart adapter/benchmark tests passed in a standalone Dart runner
  using platform-channel/SafeBoot stubs. The new tests exercise late-start
  disposal, stop/restart ordering, transient Safe Mode text discard, and the
  adapter-to-benchmark path with HTTP clients forbidden. Full Flutter codec,
  binding, analysis, and Windows execution remain CI/device gates.
- The PowerShell source contract passed. No model was obtained or run, and no
  real microphone/network-disabled device evidence has been collected.

Use synthetic phrases; retain metrics and pass/fail evidence, not audio or
transcripts. Fill this record after running the enabled Windows build:

| Device-only check | Status / evidence |
| --- | --- |
| Windows/build SHA, CPU, microphone, SDK/DLL versions, profile/model SHA-256 | Pending |
| Network adapters disabled: local model loads; partial/final recognition works | Pending |
| Missing/wrong model, runtime opt-out, remote/reparse/cloud paths: unavailable, mic off | Pending |
| Repeated start/stop, denied permission, unplugged mic: no remaining capture | Pending |
| Safe Mode during capture and immediately after start: mic off before stop completes; no late text | Pending |
| Benchmark output/logs contain metrics only; accuracy, latency and memory budgets recorded separately | Pending |

Production promotion remains blocked on these checks. Android remains
unimplemented and unavailable; WinRT and `speech_to_text` remain unverified
fallbacks. Voice-turn capture/read/correction/cloud-disclosure leases and local
journaling are outside this prototype and retain their existing boundaries.

## Device benchmark

`NeuraSpeechBenchmarkHarness` measures start latency, time to first final
segment, stop latency, resident-memory delta, package size supplied by the
packaging job, and before/after thermal state. It discards recognized text and
rejects non-local engines. Safe Mode blocks the benchmark before microphone
startup and forces a failed result if it activates during an exercise.

Run the same consented phrase set on representative low, median, and high
Windows and Android devices. Record cold and warm runs separately. Do not
promote an ONNX model until it meets release budgets for:

- p50/p95 first-final latency;
- word error rate on the supported accents and noisy-room set;
- peak and steady-state resident memory;
- installed/package size;
- sustained thermal state and battery drain;
- microphone teardown on Safe Mode, backgrounding, and cancellation; and
- offline behavior with network access disabled.

## Optional voice-turn metadata

Recognition emits confidence and pause timing on a stream separate from the
legacy transcript stream. A process-local metadata builder can derive mean
confidence, pause count, interruption count, and an optional coarse affect
label without retaining transcript text.

Capture, inspection, correction, and cloud disclosure each require a separate
short-lived, direct-gesture, single-use lease. An inferred affect label is
withheld from cloud disclosure until the user corrects or confirms it. The
store has no serialization API, clears explicitly, and is blocked in Safe
Mode.

WinRT confidence is coarse because the native API exposes
high/medium/low/rejected rather than a calibrated probability; the bridge maps
those categories to 0.90/0.65/0.35/0.0 for comparison only. Results must not be
treated as calibrated across engines.
