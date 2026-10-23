#pragma once

#include <windows.h>
// The SDK media interface has a GetCurrentTime method, not the Win32 macro.
#undef GetCurrentTime
#include <mfapi.h>
#include <mfmediaengine.h>
#include "neura_com_identity.h"

namespace media {
class MFCallbackBase;
class MediaEngineWrapper;
class MediaEngineExtension;
}  // namespace media

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

// Explicit member specializations keep the real implements<> base (including
// weak references, agility and module ownership). A derived override alone
// still instantiates the failing default virtual body. These provide the same
// name using public SDK operations; no winrt::impl metadata or SDK header edits.
template <>
inline hstring implements<media::MFCallbackBase, IMFAsyncCallback>::GetRuntimeClassName() const {
  return neura::NativeComRuntimeName<IMFAsyncCallback>();
}
template <>
inline hstring implements<media::MediaEngineWrapper, IUnknown>::GetRuntimeClassName() const {
  return neura::NativeComRuntimeName<IUnknown>();
}
template <>
inline hstring implements<media::MediaEngineExtension, IMFMediaEngineExtension>::GetRuntimeClassName() const {
  return neura::NativeComRuntimeName<IMFMediaEngineExtension>();
}
}  // namespace winrt
