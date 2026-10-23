#pragma once

#include <windows.h>
#include <NotificationActivationCallback.h>
#include "neura_com_identity.h"

namespace winrt {
template <>
inline bool is_guid_of<INotificationActivationCallback>(guid const& id) noexcept {
  return neura::MatchesNativeComIdentity<INotificationActivationCallback>(id);
}
}  // namespace winrt
