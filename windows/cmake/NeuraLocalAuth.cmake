# local_auth_windows 2.0.2 mixes C++20 with legacy /await. Its source also
# returns a value from a coroutine, and routes a native COM IID through a
# constexpr __uuidof conversion that CodeQL 2.27.3 cannot extract. Build the
# same reviewed source correction in production and security builds. Never
# modify the package cache, replace SDK headers, or omit the plugin.
function(neura_prepare_local_auth_source source output_dir)
  file(READ "${source}" original)
  string(REPLACE "\r\n" "\n" original "${original}")
  string(SHA256 source_sha "${original}")
  if(NOT source_sha STREQUAL
      "5d95868f9f8ac2c937a8f0249f7e4584373e4151f82ad71827f15f5e8d5c8c9f")
    message(FATAL_ERROR
      "local_auth_windows source changed; review the C++20/COM correction before building")
  endif()

  string(REPLACE "#include <winstring.h>"
    "#include <winstring.h>\n#include <roapi.h>" patched "${original}")
  string(REPLACE [=[    winrt::impl::com_ref<IUserConsentVerifierInterop>
        user_consent_verifier_interop = winrt::get_activation_factory<
            winrt::Windows::Security::Credentials::UI::UserConsentVerifier,
            IUserConsentVerifierInterop>();]=]
    [=[    winrt::com_ptr<IUserConsentVerifierInterop> user_consent_verifier_interop;
    auto class_name = winrt::hstring(winrt::name_of<
        winrt::Windows::Security::Credentials::UI::UserConsentVerifier>());
    winrt::check_hresult(::RoGetActivationFactory(
        static_cast<HSTRING>(winrt::get_abi(class_name)),
        __uuidof(IUserConsentVerifierInterop),
        user_consent_verifier_interop.put_void()));]=] patched "${patched}")
  string(REPLACE "    return consent_result;" "    co_return consent_result;"
    patched "${patched}")
  if(patched MATCHES "winrt::impl::com_ref<IUserConsentVerifierInterop>" OR
      NOT patched MATCHES "::RoGetActivationFactory" OR
      NOT patched MATCHES "co_return consent_result;")
    message(FATAL_ERROR "Expected complete local_auth coroutine/COM correction")
  endif()

  file(MAKE_DIRECTORY "${output_dir}")
  file(WRITE "${output_dir}/local_auth_plugin.cpp" "${patched}")
  string(SHA256 patched_sha "${patched}")
  file(WRITE "${output_dir}/local_auth_source_receipt.txt"
    "local_auth_windows 2.0.2\nupstream_sha256=${source_sha}\nbuild_sha256=${patched_sha}\n")
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${source}")
endfunction()

function(neura_configure_local_auth output_dir)
  set(plugin local_auth_windows_plugin)
  if(NOT TARGET ${plugin})
    message(FATAL_ERROR "Expected genuine local_auth_windows plugin target")
  endif()
  get_target_property(plugin_dir ${plugin} SOURCE_DIR)
  neura_prepare_local_auth_source("${plugin_dir}/local_auth_plugin.cpp" "${output_dir}")
  configure_file("${plugin_dir}/../LICENSE" "${output_dir}/LICENSE" COPYONLY)

  get_target_property(sources ${plugin} SOURCES)
  list(FIND sources "local_auth_plugin.cpp" source_index)
  if(source_index EQUAL -1)
    message(FATAL_ERROR "local_auth_windows source layout changed; review before building")
  endif()
  list(REMOVE_AT sources ${source_index})
  list(APPEND sources "${output_dir}/local_auth_plugin.cpp")
  set_property(TARGET ${plugin} PROPERTY SOURCES "${sources}")
  target_include_directories(${plugin} PRIVATE "${plugin_dir}")
  target_link_libraries(${plugin} PRIVATE RuntimeObject.lib)

  get_target_property(options ${plugin} COMPILE_OPTIONS)
  list(FIND options "/await" await_index)
  if(await_index EQUAL -1)
    message(FATAL_ERROR "local_auth_windows coroutine flags changed; review before building")
  endif()
  list(REMOVE_AT options ${await_index})
  set_property(TARGET ${plugin} PROPERTY COMPILE_OPTIONS "${options}")
  # The plugin already requests cxx_std_20. Standard coroutines use the real
  # <coroutine> header and do not need /await (the incompatible legacy ABI).
endfunction()
