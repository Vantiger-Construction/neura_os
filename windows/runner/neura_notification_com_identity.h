#pragma once

#include <windows.h>
#include <NotificationActivationCallback.h>
#include "neura_com_identity.h"

struct NotificationActivationCallback;
struct NotificationActivationCallbackFactory;

namespace winrt {
template <>
inline bool is_guid_of<INotificationActivationCallback>(guid const& id) noexcept {
  return neura::MatchesNativeComIdentity<INotificationActivationCallback>(id);
}
template <>
inline hstring implements<NotificationActivationCallback, INotificationActivationCallback>::GetRuntimeClassName() const {
  return neura::NativeComRuntimeName<INotificationActivationCallback>();
}
template <>
inline hstring implements<NotificationActivationCallbackFactory, IClassFactory>::GetRuntimeClassName() const {
  return neura::NativeComRuntimeName<IClassFactory>();
}
}  // namespace winrt
