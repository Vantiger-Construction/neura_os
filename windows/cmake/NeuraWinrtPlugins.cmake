function(neura_prepare_media_source source output_dir)
  file(READ "${source}" original)
  string(REPLACE "\r\n" "\n" original "${original}")
  string(SHA256 source_sha "${original}")
  if(NOT source_sha STREQUAL
      "24d5d72bbb96836b83a5dd851399a8e00eadf37a957a827c24eeb442499098ac")
    message(FATAL_ERROR "audioplayers_windows source changed; review COM correction before building")
  endif()
  string(REPLACE [=[    winrt::com_ptr<IMFMediaEngineEx> mediaEngineEx =
        m_mediaEngine.as<IMFMediaEngineEx>();]=]
    [=[    winrt::com_ptr<IMFMediaEngineEx> mediaEngineEx;
    winrt::check_hresult(m_mediaEngine->QueryInterface(
        __uuidof(IMFMediaEngineEx), mediaEngineEx.put_void()));]=]
    patched "${original}")
  string(REPLACE [=[  winrt::com_ptr<IMFMediaEngineEx> mediaEngineEx =
      m_mediaEngine.as<IMFMediaEngineEx>();]=]
    [=[  winrt::com_ptr<IMFMediaEngineEx> mediaEngineEx;
  winrt::check_hresult(m_mediaEngine->QueryInterface(
      __uuidof(IMFMediaEngineEx), mediaEngineEx.put_void()));]=]
    patched "${patched}")
  string(REPLACE [=[};
}  // namespace

// Public methods]=]
    [=[};
}  // namespace
}  // namespace media

namespace winrt {
template <>
inline hstring implements<media::MediaEngineCallbackHelper,
    IMFMediaEngineNotify>::GetRuntimeClassName() const {
  return neura::NativeComRuntimeName<IMFMediaEngineNotify>();
}
}  // namespace winrt

namespace media {

// Public methods]=]
    patched "${patched}")
  if(patched MATCHES "as<IMFMediaEngineEx>" OR
      NOT patched MATCHES "GetRuntimeClassName")
    message(FATAL_ERROR "Expected complete media COM correction before building")
  endif()
  file(MAKE_DIRECTORY "${output_dir}")
  file(WRITE "${output_dir}/MediaEngineWrapper.cpp" "${patched}")
  string(SHA256 patched_sha "${patched}")
  file(WRITE "${output_dir}/media_source_receipt.txt"
    "audioplayers_windows 4.4.1\nupstream_sha256=${source_sha}\nbuild_sha256=${patched_sha}\n")
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${source}")
endfunction()

function(neura_read_pinned_com_source path expected output)
  file(READ "${path}" original)
  string(REPLACE "\r\n" "\n" original "${original}")
  string(SHA256 actual "${original}")
  if(NOT actual STREQUAL expected)
    message(FATAL_ERROR "Native COM source changed: ${path}; review before building")
  endif()
  set(${output} "${original}" PARENT_SCOPE)
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${path}")
endfunction()

function(neura_prepare_media_headers source_dir output_dir)
  neura_read_pinned_com_source("${source_dir}/MediaFoundationHelpers.h"
    "4e1acc35beabc3773c2136bb0d42b2def6ea19d6c22c052fcaf0eefcace3b300" helpers)
  string(REPLACE [=[class SyncMFCallback : public MFCallbackBase {]=]
    [=[}  // namespace media
namespace winrt {
template <>
inline hstring implements<media::MFCallbackBase, IMFAsyncCallback>::GetRuntimeClassName() const {
  return neura::NativeComRuntimeName<IMFAsyncCallback>();
}
}  // namespace winrt
namespace media {

class SyncMFCallback : public MFCallbackBase {]=] helpers "${helpers}")
  file(WRITE "${output_dir}/MediaFoundationHelpers.h" "${helpers}")
  foreach(entry IN ITEMS
      "MediaEngineWrapper.h|930b94cf1a0891ec32e68ffb6be7c3dd241ca9cd5a1fea946430c5a03d454367|MediaEngineWrapper|IUnknown"
      "MediaEngineExtension.h|3145ddf892f86b1f255093b7a786031eeb9033e6b6ab139a9377907627496818|MediaEngineExtension|IMFMediaEngineExtension")
    string(REPLACE "|" ";" fields "${entry}")
    list(GET fields 0 filename)
    list(GET fields 1 expected)
    list(GET fields 2 implementation)
    list(GET fields 3 interface)
    neura_read_pinned_com_source("${source_dir}/${filename}" "${expected}" header)
    string(APPEND header "\nnamespace winrt {\ntemplate <>\ninline hstring implements<media::${implementation}, ${interface}>::GetRuntimeClassName() const {\n  return neura::NativeComRuntimeName<${interface}>();\n}\n}  // namespace winrt\n")
    file(WRITE "${output_dir}/${filename}" "${header}")
  endforeach()
  foreach(filename IN ITEMS MediaFoundationHelpers.h MediaEngineWrapper.h MediaEngineExtension.h)
    file(READ "${source_dir}/${filename}" upstream)
    string(REPLACE "\r\n" "\n" upstream "${upstream}")
    string(SHA256 upstream_sha "${upstream}")
    file(SHA256 "${output_dir}/${filename}" compiled_sha)
    file(APPEND "${output_dir}/media_source_receipt.txt"
      "${filename}: upstream_sha256=${upstream_sha}; build_sha256=${compiled_sha}\n")
  endforeach()
endfunction()

function(neura_prepare_notification_source source output_dir)
  neura_read_pinned_com_source("${source}"
    "e56a6c1939fad6656f136cc7e31803b8544637af78002e275921888ca46ecb65" original)
  string(REPLACE [=[/// A class factory that creates an instance of NotificationActivationCallback.]=]
    [=[namespace winrt {
template <>
inline hstring implements<NotificationActivationCallback, INotificationActivationCallback>::GetRuntimeClassName() const {
  return neura::NativeComRuntimeName<INotificationActivationCallback>();
}
}  // namespace winrt

/// A class factory that creates an instance of NotificationActivationCallback.]=] patched "${original}")
  string(REPLACE [=[/// Updates the Registry to enable notifications.]=]
    [=[namespace winrt {
template <>
inline hstring implements<NotificationActivationCallbackFactory, IClassFactory>::GetRuntimeClassName() const {
  return neura::NativeComRuntimeName<IClassFactory>();
}
}  // namespace winrt

/// Updates the Registry to enable notifications.]=] patched "${patched}")
  file(MAKE_DIRECTORY "${output_dir}")
  file(WRITE "${output_dir}/plugin.cpp" "${patched}")
  string(SHA256 upstream_sha "${original}")
  string(SHA256 compiled_sha "${patched}")
  file(WRITE "${output_dir}/notification_source_receipt.txt"
    "flutter_local_notifications_windows 3.1.1\nupstream_sha256=${upstream_sha}\nbuild_sha256=${compiled_sha}\n")
endfunction()

function(neura_configure_winrt_plugins output_dir identity_headers)
  # permission_handler_windows 0.2.2 already uses standard co_return. Match
  # its requested C++20 mode instead of enabling the incompatible legacy ABI.
  set(permission permission_handler_windows_plugin)
  if(NOT TARGET ${permission})
    message(FATAL_ERROR "Expected genuine permission_handler_windows target")
  endif()
  get_target_property(options ${permission} COMPILE_OPTIONS)
  list(FIND options "/await" await_index)
  if(await_index EQUAL -1)
    message(FATAL_ERROR "permission_handler_windows coroutine flags changed; review before building")
  endif()
  list(REMOVE_AT options ${await_index})
  set_property(TARGET ${permission} PROPERTY COMPILE_OPTIONS "${options}")

  set(media audioplayers_windows_plugin)
  set(notifications flutter_local_notifications_windows)
  if(NOT TARGET ${media} OR NOT TARGET ${notifications})
    message(FATAL_ERROR "Expected genuine media and notifications targets")
  endif()
  get_target_property(media_dir ${media} SOURCE_DIR)
  # Copy every genuine package file so quoted includes resolve the reviewed
  # class definitions consistently in every media translation unit. No source
  # is omitted; all target entries are mapped one-for-one to this full copy.
  file(COPY "${media_dir}/" DESTINATION "${output_dir}")
  neura_prepare_media_source("${media_dir}/MediaEngineWrapper.cpp" "${output_dir}")
  neura_prepare_media_headers("${media_dir}" "${output_dir}")
  configure_file("${media_dir}/../LICENSE" "${output_dir}/LICENSE" COPYONLY)
  get_target_property(sources ${media} SOURCES)
  set(compiled_sources "")
  foreach(source IN LISTS sources)
    if(IS_ABSOLUTE "${source}" OR NOT EXISTS "${media_dir}/${source}")
      message(FATAL_ERROR "audioplayers_windows source layout changed; review before building")
    endif()
    list(APPEND compiled_sources "${output_dir}/${source}")
  endforeach()
  set_property(TARGET ${media} PROPERTY SOURCES "${compiled_sources}")
  target_include_directories(${media} PRIVATE "${output_dir}" "${media_dir}")

  get_target_property(notification_dir ${notifications} SOURCE_DIR)
  set(notification_output "${output_dir}/notifications")
  neura_prepare_notification_source("${notification_dir}/plugin.cpp" "${notification_output}")
  configure_file("${notification_dir}/../LICENSE" "${notification_output}/LICENSE" COPYONLY)
  get_target_property(notification_sources ${notifications} SOURCES)
  list(FIND notification_sources "plugin.cpp" notification_index)
  if(notification_index EQUAL -1)
    message(FATAL_ERROR "Notification source layout changed; review before building")
  endif()
  list(REMOVE_AT notification_sources ${notification_index})
  list(APPEND notification_sources "${notification_output}/plugin.cpp")
  set_property(TARGET ${notifications} PROPERTY SOURCES "${notification_sources}")
  target_include_directories(${notifications} PRIVATE "${notification_dir}")
  target_compile_options(${media} PRIVATE "/FI${identity_headers}/neura_media_winrt.h")
  target_compile_options(${notifications} PRIVATE "/FI${identity_headers}/neura_notification_com_identity.h")
endfunction()
