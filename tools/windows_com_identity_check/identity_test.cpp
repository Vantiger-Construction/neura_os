#include "neura_media_com_identity.h"
#include "neura_notification_com_identity.h"

#include <array>
#include <cstdio>

namespace neura_com_test {
namespace {
int destroyed = 0;
}  // namespace

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
}  // namespace neura_com_test

// Define these after the implementation types are complete, before allocation.
namespace winrt {
template <>
inline hstring implements<neura_com_test::AudioCallback, IMFAsyncCallback>::GetRuntimeClassName() const {
  return neura::NativeComRuntimeName<IMFAsyncCallback>();
}
template <>
inline hstring implements<neura_com_test::NotificationCallback,
    INotificationActivationCallback>::GetRuntimeClassName() const {
  return neura::NativeComRuntimeName<INotificationActivationCallback>();
}
}  // namespace winrt

namespace neura_com_test {

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

template <typename Interface>
bool RuntimeNameWorks() {
  // Compare with the genuine Win32 formatter, normalizing only hexadecimal
  // case to C++/WinRT's lowercase, braced GUID convention. No copied UUIDs.
  wchar_t expected[40]{};
  if (StringFromGUID2(__uuidof(Interface), expected, 40) != 39) return false;
  for (auto& c : expected) {
    if (c >= L'A' && c <= L'F') c += L'a' - L'A';
  }
  return neura::NativeComRuntimeName<Interface>() == expected;
}
}  // namespace neura_com_test

int main() {
  using namespace neura_com_test;
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
  if (!RuntimeNameWorks<IUnknown>() || !RuntimeNameWorks<IClassFactory>() ||
      !RuntimeNameWorks<IMFAsyncCallback>() || !RuntimeNameWorks<IMFMediaEngineExtension>() ||
      !RuntimeNameWorks<IMFMediaEngineNotify>() ||
      !RuntimeNameWorks<INotificationActivationCallback>()) return 4;
  std::puts("SDK IID matrix, GUID names, QueryInterface rejection and COM ownership passed; no devices activated.");
  return 0;
}
