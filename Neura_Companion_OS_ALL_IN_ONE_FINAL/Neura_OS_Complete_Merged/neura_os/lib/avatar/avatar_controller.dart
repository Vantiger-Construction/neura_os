/// SHIM NOTE:
/// If your project already has AvatarController elsewhere, delete this file.
/// This shim exists only to keep this patch self-contained in isolation.
///
/// Expected API used by the fault system:
/// - setError(bool)
/// - pulseBlink()
/// - pulseWave()
abstract class AvatarController {
  void setError(bool v);
  void pulseBlink();
  void pulseWave();
}
