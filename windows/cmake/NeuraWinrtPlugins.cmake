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
  file(MAKE_DIRECTORY "${output_dir}")
  file(WRITE "${output_dir}/MediaEngineWrapper.cpp" "${patched}")
  string(SHA256 patched_sha "${patched}")
  file(WRITE "${output_dir}/media_source_receipt.txt"
    "audioplayers_windows 4.4.1\nupstream_sha256=${source_sha}\nbuild_sha256=${patched_sha}\n")
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${source}")
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
  neura_prepare_media_source("${media_dir}/MediaEngineWrapper.cpp" "${output_dir}")
  configure_file("${media_dir}/../LICENSE" "${output_dir}/LICENSE" COPYONLY)
  get_target_property(sources ${media} SOURCES)
  list(FIND sources "MediaEngineWrapper.cpp" source_index)
  if(source_index EQUAL -1)
    message(FATAL_ERROR "audioplayers_windows source layout changed; review before building")
  endif()
  list(REMOVE_AT sources ${source_index})
  list(APPEND sources "${output_dir}/MediaEngineWrapper.cpp")
  set_property(TARGET ${media} PROPERTY SOURCES "${sources}")
  target_include_directories(${media} PRIVATE "${media_dir}")
  target_compile_options(${media} PRIVATE "/FI${identity_headers}/neura_media_winrt.h")
  target_compile_options(${notifications} PRIVATE "/FI${identity_headers}/neura_notification_com_identity.h")
endfunction()
