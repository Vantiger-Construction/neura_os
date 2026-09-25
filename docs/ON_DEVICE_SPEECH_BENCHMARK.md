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

The ONNX adapter is intentionally unavailable until a Windows or Android
runner implements `neura/on_device_asr` and reports `isAvailable: true`.
No model binary, download, license, or claimed accuracy is hidden in this
change. Production selection continues to use the existing engines.

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
