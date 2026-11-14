# window_manager_plus 1.0.5 replaces its bootstrap channel with an ID-scoped
# channel on first initialization. A Dart hot restart loses its singleton but
# keeps the native engine, so the next ensureInitialized has no native handler.
# Keep a separate bootstrap channel for the native plugin's entire lifetime.
# As with the other reviewed plugin fixes, patch a hash-guarded build-local copy
# and leave the dependency cache and public plugin interface unchanged.
function(neura_prepare_window_manager_source source output_dir)
  file(READ "${source}" original)
  string(REPLACE "\r\n" "\n" original "${original}")
  string(SHA256 source_sha "${original}")
  if(NOT source_sha STREQUAL
      "661e5a48701afe1bd46c2917d7de87ff1926b06b9159fbbfa5fd33a776db82ab")
    message(FATAL_ERROR
      "window_manager_plus source changed; review hot-restart channel ownership before building")
  endif()

  string(REPLACE
    "  std::shared_ptr<WindowManagerPlus> window_manager;"
    "  std::shared_ptr<WindowManagerPlus> window_manager;\n  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> bootstrap_channel_;"
    patched "${original}")
  string(REPLACE [=[  window_manager->channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "window_manager_plus",
          &flutter::StandardMethodCodec::GetInstance());
  window_manager->channel->SetMethodCallHandler(]=]
    [=[  bootstrap_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "window_manager_plus",
          &flutter::StandardMethodCodec::GetInstance());
  bootstrap_channel_->SetMethodCallHandler(]=] patched "${patched}")
  string(REPLACE
    "  registrar->UnregisterTopLevelWindowProcDelegate(window_proc_id);"
    [=[  bootstrap_channel_->SetMethodCallHandler(nullptr);
  if (window_manager->channel) {
    window_manager->channel->SetMethodCallHandler(nullptr);
  }
  registrar->UnregisterTopLevelWindowProcDelegate(window_proc_id);]=]
    patched "${patched}")
  if(NOT patched MATCHES "bootstrap_channel_ =" OR
      NOT patched MATCHES "bootstrap_channel_->SetMethodCallHandler\\(nullptr\\)")
    message(FATAL_ERROR "Expected complete window_manager_plus channel ownership correction")
  endif()

  file(MAKE_DIRECTORY "${output_dir}")
  file(WRITE "${output_dir}/window_manager_plus_plugin.cpp" "${patched}")
  string(SHA256 patched_sha "${patched}")
  file(WRITE "${output_dir}/window_manager_source_receipt.txt"
    "window_manager_plus 1.0.5\nupstream_sha256=${source_sha}\nbuild_sha256=${patched_sha}\n")
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${source}")
endfunction()

function(neura_configure_window_manager output_dir)
  set(plugin window_manager_plus_plugin)
  if(NOT TARGET ${plugin})
    message(FATAL_ERROR "Expected genuine window_manager_plus plugin target")
  endif()
  get_target_property(plugin_dir ${plugin} SOURCE_DIR)
  neura_prepare_window_manager_source("${plugin_dir}/window_manager_plus_plugin.cpp" "${output_dir}")
  configure_file("${plugin_dir}/../LICENSE" "${output_dir}/LICENSE" COPYONLY)

  get_target_property(sources ${plugin} SOURCES)
  list(FIND sources "window_manager_plus_plugin.cpp" source_index)
  if(source_index EQUAL -1)
    message(FATAL_ERROR "window_manager_plus source layout changed; review before building")
  endif()
  list(REMOVE_AT sources ${source_index})
  list(APPEND sources "${output_dir}/window_manager_plus_plugin.cpp")
  set_property(TARGET ${plugin} PROPERTY SOURCES "${sources}")
  target_include_directories(${plugin} PRIVATE "${plugin_dir}")
endfunction()
