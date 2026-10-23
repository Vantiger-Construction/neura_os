#include "neura_media_com_identity.h"
#include "neura_notification_com_identity.h"

#include <array>
#include <cstdio>

namespace {
int destroyed = 0;

// Exercise the actual C++/WinRT QueryInterface and ownership implementation.
// These in-memory test objects never activate notifications or audio devices.
struct AudioCallback : winrt::implements<AudioCallback, IMFAsyncCallback> {
  ~AudioCallback() { ++destroyed; }
  HRESULT __stdcall GetParameters(DWORD*, DWORD*) noexcept final { return E_NOTIMPL; }
  HRESULT __stdcall Invoke(IMFAsyncResult*) noexcept final { return E_NOTIMPL; }
};

struct NotificationCallback
    : winrt::implements<NotificationCallback, INotificationActivationCallback> {
  ~NotificationCallback() { ++destroyed; }
  HRESULT __stdcall Activate(LPCWSTR, LPCWSTR,
      NOTIFICATION_USER_INPUT_DATA const*, ULONG) noexcept final { return E_NOTIMPL; }
};

template <typename Callback, typename Interface>
bool QueryWorks(Callback* object) {
  winrt::com_ptr<IUnknown> result;
  if (object->QueryInterface(__uuidof(Interface), result.put_void()) != S_OK || !result) {
    return false;
  }
  result = nullptr;
  // A failed lookup must clear the output and must not expose another vtable.
  return object->QueryInterface(__uuidof(IClassFactory), result.put_void()) == E_NOINTERFACE
      && !result;
}
}  // namespace

int main() {
  using Check = bool (*)(winrt::guid const&) noexcept;
  const std::array<Check, 6> checks = {
      &winrt::is_guid_of<IUnknown>, &winrt::is_guid_of<IClassFactory>,
      &winrt::is_guid_of<IMFAsyncCallback>, &winrt::is_guid_of<IMFMediaEngineExtension>,
      &winrt::is_guid_of<IMFMediaEngineNotify>, &winrt::is_guid_of<INotificationActivationCallback>};
  const std::array<winrt::guid, 6> ids = {
      winrt::guid{__uuidof(IUnknown)}, winrt::guid{__uuidof(IClassFactory)},
      winrt::guid{__uuidof(IMFAsyncCallback)}, winrt::guid{__uuidof(IMFMediaEngineExtension)},
      winrt::guid{__uuidof(IMFMediaEngineNotify)}, winrt::guid{__uuidof(INotificationActivationCallback)}};
  for (size_t i = 0; i < checks.size(); ++i) {
    for (size_t j = 0; j < ids.size(); ++j) {
      if (checks[i](ids[j]) != (i == j)) return 1;
    }
  }
  {
    auto audio = winrt::make_self<AudioCallback>();
    auto notification = winrt::make_self<NotificationCallback>();
    if (!QueryWorks<AudioCallback, IMFAsyncCallback>(audio.get()) ||
        !QueryWorks<NotificationCallback, INotificationActivationCallback>(notification.get())) return 2;
  }
  if (destroyed != 2) return 3;
  std::puts("SDK IID matrix, QueryInterface rejection and COM ownership passed; no devices activated.");
  return 0;
}
