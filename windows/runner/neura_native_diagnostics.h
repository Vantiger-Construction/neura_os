#ifndef RUNNER_NEURA_NATIVE_DIAGNOSTICS_H_
#define RUNNER_NEURA_NATIVE_DIAGNOSTICS_H_

// Initializes Neura's best-effort Windows runner diagnostics and records the
// first startup breadcrumb. Safe to call more than once.
//
// Records contain only timestamps, fixed lifecycle labels, process/thread
// identifiers, exception codes, fault addresses, and a faulting module's base
// filename. They never include command-line arguments, user content, memory
// dumps, or full filesystem paths.
void InitializeNeuraNativeDiagnostics();

// Reinstalls the process-level crash handlers. Flutter or a native plugin can
// replace an unhandled-exception filter while its engine is being created, so
// the runner calls this again after plugin registration.
void InstallNeuraNativeCrashHandlers();

// Appends a fixed, non-user-controlled runner lifecycle event.
void RecordNeuraNativeBreadcrumb(const char* event_name);

// Permanently disables native diagnostic writes for this process. The Dart
// full-data-wipe path calls this before deleting the shared crash vault so a
// later message-loop exit cannot recreate a wiped record.
void SuspendNeuraNativeDiagnosticsForDataWipe();

#endif  // RUNNER_NEURA_NATIVE_DIAGNOSTICS_H_
