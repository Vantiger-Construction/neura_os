# Windows speech belongs exclusively to Neura's local SAPI owner. Flutter
# regenerates its plugin files; filter build-local copies instead of editing them.
function(neura_prepare_windows_plugins registrant plugins output_dir)
  file(READ "${registrant}" registration_source)
  string(REPLACE "\r\n" "\n" registration_source "${registration_source}")
  string(REPLACE "#include <flutter_tts/flutter_tts_plugin.h>\n" ""
    registration_source "${registration_source}")
  string(REPLACE
    "  FlutterTtsPluginRegisterWithRegistrar(\n      registry->GetRegistrarForPlugin(\"FlutterTtsPlugin\"));\n"
    "" registration_source "${registration_source}")
  # An upstream registration shape change must not silently restore this path.
  if(registration_source MATCHES "[Ff]lutter_?[Tt]ts")
    message(FATAL_ERROR "Unrecognized legacy Windows TTS registration; review generated plugin format")
  endif()

  file(READ "${plugins}" plugin_source)
  string(REPLACE "\r\n" "\n" plugin_source "${plugin_source}")
  string(REPLACE "\n  flutter_tts\n" "\n" plugin_source "${plugin_source}")
  if(plugin_source MATCHES "flutter_tts")
    message(FATAL_ERROR "Unrecognized legacy Windows TTS build entry; review generated plugin format")
  endif()
  file(MAKE_DIRECTORY "${output_dir}")
  file(WRITE "${output_dir}/generated_plugin_registrant.cc" "${registration_source}")
  file(WRITE "${output_dir}/generated_plugins.cmake" "${plugin_source}")
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${registrant}" "${plugins}")
  set(NEURA_WINDOWS_PLUGIN_REGISTRANT "${output_dir}/generated_plugin_registrant.cc" PARENT_SCOPE)
  set(NEURA_WINDOWS_PLUGIN_LIST "${output_dir}/generated_plugins.cmake" PARENT_SCOPE)
endfunction()
