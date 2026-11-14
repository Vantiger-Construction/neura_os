#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>
#include <optional>
#include <cstdlib>

#include "utils.h"
#include "win32_window.h"

namespace {

// Separate host, not a switch inside the production startup path. Nothing here
// registers plugins or constructs Neura storage, diagnostic, speech or engines.
class DemoWindow final : public Win32Window {
 public:
  ~DemoWindow() override = default;

 protected:
  bool OnCreate() override {
    if (!Win32Window::OnCreate()) return false;
    const RECT frame = GetClientArea();
    flutter::DartProject project(L"data");
    controller_ = std::make_unique<flutter::FlutterViewController>(
        frame.right - frame.left, frame.bottom - frame.top, project);
    if (!controller_->engine() || !controller_->view()) return false;
    channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        controller_->engine()->messenger(), "neura/isolated_preview",
        &flutter::StandardMethodCodec::GetInstance());
    channel_->SetMethodCallHandler([](const auto& call, auto result) {
      if (call.method_name() == "getIsolation") {
        result->Success(flutter::EncodableValue("sample-data-no-plugins-v1"));
      } else {
        result->NotImplemented();
      }
    });
    SetChildContent(controller_->view()->GetNativeWindow());
    controller_->engine()->SetNextFrameCallback([this]() {
      ::ShowWindow(GetHandle(), SW_SHOWMAXIMIZED);
    });
    controller_->ForceRedraw();
    return true;
  }

  void OnDestroy() override {
    channel_.reset();
    controller_.reset();
    Win32Window::OnDestroy();
  }

  LRESULT MessageHandler(HWND hwnd, UINT message, WPARAM wparam,
                         LPARAM lparam) noexcept override {
    if (controller_) {
      const std::optional<LRESULT> result =
          controller_->HandleTopLevelWindowProc(hwnd, message, wparam, lparam);
      if (result) return *result;
    }
    return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
  }

 private:
  std::unique_ptr<flutter::FlutterViewController> controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE previous,
                     _In_ wchar_t* command_line, _In_ int show_command) {
  HANDLE mutex = ::CreateMutexW(nullptr, FALSE,
      L"Local\\NeuraCompanionIsolatedPreview-v1");
  const DWORD error = ::GetLastError();
  if (!mutex) return EXIT_FAILURE;
  if (error == ERROR_ALREADY_EXISTS) { ::CloseHandle(mutex); return EXIT_SUCCESS; }
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }
  DemoWindow window;
  if (!window.Create(L"Neura - Sample data preview", {10, 10}, {1280, 720})) {
    ::CloseHandle(mutex);
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);
  MSG message;
  BOOL status;
  while ((status = ::GetMessage(&message, nullptr, 0, 0)) > 0) {
    ::TranslateMessage(&message);
    ::DispatchMessage(&message);
  }
  ::CloseHandle(mutex);
  return status == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
