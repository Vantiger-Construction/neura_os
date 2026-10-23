#pragma once

#include <windows.h>
// The SDK media interface has a GetCurrentTime method, not the Win32 macro.
#undef GetCurrentTime
#include <mfapi.h>
#include <mfmediaengine.h>
#include "neura_com_identity.h"

namespace winrt {
template <>
inline bool is_guid_of<IMFAsyncCallback>(guid const& id) noexcept {
  return neura::MatchesNativeComIdentity<IMFAsyncCallback>(id);
}
template <>
inline bool is_guid_of<IMFMediaEngineExtension>(guid const& id) noexcept {
  return neura::MatchesNativeComIdentity<IMFMediaEngineExtension>(id);
}
template <>
inline bool is_guid_of<IMFMediaEngineNotify>(guid const& id) noexcept {
  return neura::MatchesNativeComIdentity<IMFMediaEngineNotify>(id);
}
}  // namespace winrt
