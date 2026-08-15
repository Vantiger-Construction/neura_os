/// Process exit is intentionally unavailable in browser builds. Main never
/// activates launch-smoke mode on web.
Never exitNeuraProcess(int code) {
  throw UnsupportedError('Process exit is unavailable in browser builds.');
}
