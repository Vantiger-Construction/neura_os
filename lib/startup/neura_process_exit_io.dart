import 'dart:io';

/// Terminates a native smoke-test process with an explicit result code.
Never exitNeuraProcess(int code) => exit(code);
