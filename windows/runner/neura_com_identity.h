#pragma once

// Genuine SDK interfaces and C++/WinRT's documented is_guid_of extension
// point. Preserve native COM identity without requiring the extractor to
// constant-evaluate Microsoft's __uuidof storage through winrt::guid.
// These definitions are used in production builds as well as analysis.
#include <windows.h>
#include <unknwn.h>
#include <winrt/base.h>

namespace neura {
template <typename Interface>
inline bool MatchesNativeComIdentity(winrt::guid const& id) noexcept {
  return id == winrt::guid{__uuidof(Interface)};
}
}  // namespace neura

// Microsoft explicitly supports specializing is_guid_of. Each specialization
// accepts exactly the genuine SDK IID, just like the default implementation.
// No interface declaration, UUID, SDK header, or QueryInterface is replaced.
namespace winrt {
template <>
inline bool is_guid_of<IUnknown>(guid const& id) noexcept {
  return neura::MatchesNativeComIdentity<IUnknown>(id);
}
template <>
inline bool is_guid_of<IClassFactory>(guid const& id) noexcept {
  return neura::MatchesNativeComIdentity<IClassFactory>(id);
}
}  // namespace winrt
