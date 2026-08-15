#include "neura_native_diagnostics.h"

#include <windows.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cwchar>
#include <exception>
#include <iterator>

namespace {

constexpr wchar_t kVaultName[] = L"neura_error_vault.jsonl";
constexpr ULONGLONG kMaxVaultBytes = 512ULL * 1024ULL;
constexpr int kMaxBackupFiles = 3;

wchar_t g_vault_path[MAX_PATH] = {};
volatile LONG g_initialized = 0;
volatile LONG g_crash_recorded = 0;
volatile LONG g_suspended_for_data_wipe = 0;
SRWLOCK g_write_lock = SRWLOCK_INIT;
LPTOP_LEVEL_EXCEPTION_FILTER g_previous_exception_filter = nullptr;

bool InitializeVaultPath() {
  if (g_vault_path[0] != L'\0') {
    return true;
  }

  wchar_t temporary_directory[MAX_PATH] = {};
  const DWORD length =
      GetTempPathW(static_cast<DWORD>(std::size(temporary_directory)),
                   temporary_directory);
  if (length == 0 ||
      length >= static_cast<DWORD>(std::size(temporary_directory))) {
    return false;
  }

  if (wcscpy_s(g_vault_path, std::size(g_vault_path),
               temporary_directory) != 0 ||
      wcscat_s(g_vault_path, std::size(g_vault_path), kVaultName) != 0) {
    g_vault_path[0] = L'\0';
    return false;
  }
  return true;
}

void BuildBackupPath(int index, wchar_t (&path)[MAX_PATH]) {
  path[0] = L'\0';
  if (g_vault_path[0] == L'\0') {
    return;
  }
  swprintf_s(path, std::size(path), L"%ls.%d", g_vault_path, index);
}

void RotateVaultIfNeeded() {
  if (!InitializeVaultPath()) {
    return;
  }

  WIN32_FILE_ATTRIBUTE_DATA attributes = {};
  if (!GetFileAttributesExW(g_vault_path, GetFileExInfoStandard,
                            &attributes)) {
    return;
  }
  ULARGE_INTEGER size = {};
  size.LowPart = attributes.nFileSizeLow;
  size.HighPart = attributes.nFileSizeHigh;
  if (size.QuadPart < kMaxVaultBytes) {
    return;
  }

  wchar_t oldest[MAX_PATH] = {};
  BuildBackupPath(kMaxBackupFiles, oldest);
  DeleteFileW(oldest);
  for (int index = kMaxBackupFiles - 1; index >= 1; --index) {
    wchar_t source[MAX_PATH] = {};
    wchar_t destination[MAX_PATH] = {};
    BuildBackupPath(index, source);
    BuildBackupPath(index + 1, destination);
    MoveFileExW(source, destination, MOVEFILE_REPLACE_EXISTING);
  }
  wchar_t first_backup[MAX_PATH] = {};
  BuildBackupPath(1, first_backup);
  MoveFileExW(g_vault_path, first_backup, MOVEFILE_REPLACE_EXISTING);
}

void AppendLine(const char* line) {
  if (line == nullptr || !TryAcquireSRWLockExclusive(&g_write_lock)) {
    return;
  }

  if (InterlockedCompareExchange(&g_suspended_for_data_wipe, 0, 0) != 0 ||
      !InitializeVaultPath()) {
    ReleaseSRWLockExclusive(&g_write_lock);
    return;
  }

  HANDLE file = CreateFileW(
      g_vault_path, FILE_APPEND_DATA,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
      OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL | FILE_FLAG_WRITE_THROUGH, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    ReleaseSRWLockExclusive(&g_write_lock);
    return;
  }

  char record[1024] = {};
  const size_t line_length = strlen(line);
  if (line_length >= std::size(record) - 1) {
    CloseHandle(file);
    ReleaseSRWLockExclusive(&g_write_lock);
    return;
  }
  memcpy(record, line, line_length);
  record[line_length] = '\n';
  DWORD written = 0;
  WriteFile(file, record, static_cast<DWORD>(line_length + 1), &written,
            nullptr);
  FlushFileBuffers(file);
  CloseHandle(file);
  ReleaseSRWLockExclusive(&g_write_lock);
}

void UtcTimestamp(char (&timestamp)[32]) {
  SYSTEMTIME now = {};
  GetSystemTime(&now);
  sprintf_s(timestamp, std::size(timestamp),
            "%04u-%02u-%02uT%02u:%02u:%02u.%03uZ", now.wYear, now.wMonth,
            now.wDay, now.wHour, now.wMinute, now.wSecond, now.wMilliseconds);
}

void FaultingModuleBaseName(const void* address, char (&module_name)[128]) {
  module_name[0] = '\0';
  if (address == nullptr) {
    return;
  }

  HMODULE module = nullptr;
  if (!GetModuleHandleExW(
          GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
              GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
          reinterpret_cast<LPCWSTR>(address), &module)) {
    return;
  }

  wchar_t module_path[MAX_PATH] = {};
  if (GetModuleFileNameW(module, module_path,
                         static_cast<DWORD>(std::size(module_path))) == 0) {
    return;
  }

  const wchar_t* base_name = module_path;
  for (const wchar_t* cursor = module_path; *cursor != L'\0'; ++cursor) {
    if (*cursor == L'\\' || *cursor == L'/') {
      base_name = cursor + 1;
    }
  }
  WideCharToMultiByte(CP_UTF8, 0, base_name, -1, module_name,
                      static_cast<int>(std::size(module_name)), nullptr,
                      nullptr);
}

LONG WINAPI NeuraUnhandledExceptionFilter(EXCEPTION_POINTERS* details) {
  if (InterlockedCompareExchange(&g_crash_recorded, 1, 0) != 0) {
    return EXCEPTION_CONTINUE_SEARCH;
  }

  const EXCEPTION_RECORD* record = details == nullptr
                                       ? nullptr
                                       : details->ExceptionRecord;
  const DWORD code = record == nullptr ? 0 : record->ExceptionCode;
  const void* address =
      record == nullptr ? nullptr : record->ExceptionAddress;
  char module_name[128] = {};
  FaultingModuleBaseName(address, module_name);
  char timestamp[32] = {};
  UtcTimestamp(timestamp);
  char line[768] = {};
  sprintf_s(
      line, std::size(line),
      "{\"ts\":\"%s\",\"type\":\"native_crash\","
      "\"source\":\"windows_runner\",\"event\":\"unhandled_exception\","
      "\"exception_code\":\"0x%08lX\",\"fault_address\":\"%p\","
      "\"fault_module\":\"%s\",\"pid\":%lu,\"thread_id\":%lu}",
      timestamp, code, const_cast<void*>(address),
      module_name[0] == '\0' ? "unknown" : module_name,
      GetCurrentProcessId(), GetCurrentThreadId());
  AppendLine(line);
  const auto previous = g_previous_exception_filter;
  if (previous != nullptr && previous != NeuraUnhandledExceptionFilter) {
    return previous(details);
  }
  return EXCEPTION_CONTINUE_SEARCH;
}

[[noreturn]] void NeuraTerminateHandler() {
  if (InterlockedCompareExchange(&g_crash_recorded, 1, 0) == 0) {
    char timestamp[32] = {};
    UtcTimestamp(timestamp);
    char line[512] = {};
    sprintf_s(
        line, std::size(line),
        "{\"ts\":\"%s\",\"type\":\"native_crash\","
        "\"source\":\"windows_runner\",\"event\":\"cpp_terminate\","
        "\"pid\":%lu,\"thread_id\":%lu}",
        timestamp, GetCurrentProcessId(), GetCurrentThreadId());
    AppendLine(line);
  }
  TerminateProcess(GetCurrentProcess(), 3);
  std::abort();
}

}  // namespace

void InstallNeuraNativeCrashHandlers() {
  const auto previous =
      SetUnhandledExceptionFilter(NeuraUnhandledExceptionFilter);
  if (previous != nullptr && previous != NeuraUnhandledExceptionFilter) {
    g_previous_exception_filter = previous;
  }
  std::set_terminate(NeuraTerminateHandler);
}

void InitializeNeuraNativeDiagnostics() {
  InstallNeuraNativeCrashHandlers();
  if (InterlockedCompareExchange(&g_initialized, 1, 0) != 0) {
    return;
  }
  if (!InitializeVaultPath()) {
    return;
  }
  RotateVaultIfNeeded();
  RecordNeuraNativeBreadcrumb("process_start");
}

void RecordNeuraNativeBreadcrumb(const char* event_name) {
  if (event_name == nullptr) {
    return;
  }
  char timestamp[32] = {};
  UtcTimestamp(timestamp);
  char line[512] = {};
  sprintf_s(
      line, std::size(line),
      "{\"ts\":\"%s\",\"type\":\"native_breadcrumb\","
      "\"source\":\"windows_runner\",\"event\":\"%s\","
      "\"pid\":%lu,\"thread_id\":%lu}",
      timestamp, event_name, GetCurrentProcessId(), GetCurrentThreadId());
  AppendLine(line);
}

void SuspendNeuraNativeDiagnosticsForDataWipe() {
  AcquireSRWLockExclusive(&g_write_lock);
  InterlockedExchange(&g_suspended_for_data_wipe, 1);
  ReleaseSRWLockExclusive(&g_write_lock);
}
