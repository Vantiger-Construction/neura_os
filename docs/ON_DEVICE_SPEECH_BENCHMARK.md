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
   `NEURA_ON_DEVICE_ASR_MODEL_DIR` to an existing local directory containing
   `encoder.int4.onnx`, `decoder.int4.onnx`, `joiner.int4.onnx`, and
   `tokens.txt`. Neura never downloads, relocates, or modifies these files.

`isAvailable` returns true only when the backend was explicitly compiled, the
runtime opt-in is exactly `1`, all four model files resolve inside that local
directory, the path is not a URL, UNC path, or remote drive, the model loads,
and a 16 kHz mono microphone stream is supported. The Dart engine remains
`experimental`, so even an available backend is excluded from ordinary engine
selection unless the caller explicitly includes experimental engines. The
first prototype emits partial/final text but deliberately does not invent
confidence or pause values that its transducer does not provide.

Run `tools/Test-NeuraWindowsOnDeviceAsrContract.ps1` to verify the default-off,
no-network-path, channel, and synchronous teardown contract. This source-level
harness is part of `Neura-FastCheck.ps1`. Device acceptance still requires a
network-disabled run with an operator-supplied model and runtime DLLs.

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
