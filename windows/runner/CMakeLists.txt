cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

if(POLICY CMP0153)
  cmake_policy(SET CMP0153 NEW)
endif()

# neura_speech_recognizer.cpp uses WinRT (Windows.Media.SpeechRecognition),
# which needs the C++/WinRT projection headers. Fetched the same way
# flutter_tts's own windows plugin fetches them for SpeechSynthesis.
find_program(NUGET_EXE NAMES nuget)
if(NOT NUGET_EXE)
    message(FATAL_ERROR "nuget.exe not found. Please install it.")
endif()

execute_process(
        COMMAND ${NUGET_EXE} install Microsoft.Windows.CppWinRT
        -Version 2.0.210503.1
        -ExcludeVersion
        -OutputDirectory ${CMAKE_BINARY_DIR}/packages
)


# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "neura_native_diagnostics.cpp"
  "neura_on_device_asr.cpp"
  "neura_speech_recognizer.cpp"
  "neura_window_role.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# neura_speech_recognizer.cpp needs C++/WinRT coroutine support (co_await).
target_compile_features(${BINARY_NAME} PUBLIC cxx_std_20)

set_target_properties(${BINARY_NAME} PROPERTIES VS_PROJECT_IMPORT
        "${CMAKE_BINARY_DIR}/packages/Microsoft.Windows.CppWinRT/build/native/Microsoft.Windows.CppWinRT.props"
)
target_link_libraries(${BINARY_NAME} PRIVATE
        "${CMAKE_BINARY_DIR}/packages/Microsoft.Windows.CppWinRT/build/native/Microsoft.Windows.CppWinRT.targets"
)

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# --- Optional verified-local Windows ASR prototype -------------------------
# OFF is intentional. Enabling the backend requires SDK paths supplied by the
# operator; CMake never downloads an SDK, runtime DLL, or speech model.
option(NEURA_ENABLE_WINDOWS_ON_DEVICE_ASR
       "Compile the opt-in Sherpa-ONNX/PortAudio ASR backend" OFF)
set(NEURA_SHERPA_ONNX_INCLUDE_DIR "" CACHE PATH
    "Directory containing sherpa-onnx/c-api/c-api.h")
set(NEURA_SHERPA_ONNX_LIBRARY "" CACHE FILEPATH
    "Sherpa-ONNX C API import or static library")
set(NEURA_PORTAUDIO_INCLUDE_DIR "" CACHE PATH
    "Directory containing portaudio.h")
set(NEURA_PORTAUDIO_LIBRARY "" CACHE FILEPATH
    "PortAudio import or static library")

if(NEURA_ENABLE_WINDOWS_ON_DEVICE_ASR)
  if(NOT EXISTS
      "${NEURA_SHERPA_ONNX_INCLUDE_DIR}/sherpa-onnx/c-api/c-api.h")
    message(FATAL_ERROR
            "NEURA_SHERPA_ONNX_INCLUDE_DIR must contain "
            "sherpa-onnx/c-api/c-api.h")
  endif()
  if(NOT EXISTS "${NEURA_PORTAUDIO_INCLUDE_DIR}/portaudio.h")
    message(FATAL_ERROR
            "NEURA_PORTAUDIO_INCLUDE_DIR must contain portaudio.h")
  endif()
  foreach(_required_library IN ITEMS
      NEURA_SHERPA_ONNX_LIBRARY
      NEURA_PORTAUDIO_LIBRARY)
    if(NOT EXISTS "${${_required_library}}" OR
       IS_DIRECTORY "${${_required_library}}")
      message(FATAL_ERROR
              "${_required_library} must name an existing local library")
    endif()
  endforeach()

  target_compile_definitions(${BINARY_NAME} PRIVATE
      NEURA_WINDOWS_ON_DEVICE_ASR=1)
  target_include_directories(${BINARY_NAME} PRIVATE
      "${NEURA_SHERPA_ONNX_INCLUDE_DIR}"
      "${NEURA_PORTAUDIO_INCLUDE_DIR}")
  target_link_libraries(${BINARY_NAME} PRIVATE
      "${NEURA_SHERPA_ONNX_LIBRARY}"
      "${NEURA_PORTAUDIO_LIBRARY}")
endif()

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# --- Rust swarm library (neura_swarm) --------------------------------------
# Loaded directly from Dart via flutter_rust_bridge FFI (dart:ffi), not
# through a Flutter plugin or method channel like neura_speech_recognizer
# above -- so no plugin registration here, it just needs to exist next to
# the exe at runtime.
find_program(CARGO_EXE NAMES cargo)
if(NOT CARGO_EXE)
    message(FATAL_ERROR "cargo not found -- install Rust (https://rustup.rs) to build neura_swarm.")
endif()

set(NEURA_SWARM_MANIFEST "${CMAKE_CURRENT_SOURCE_DIR}/../../rust/Cargo.toml")
set(NEURA_SWARM_DLL "${CMAKE_CURRENT_SOURCE_DIR}/../../rust/target/release/neura_swarm.dll")

add_custom_target(neura_swarm_rust ALL
        COMMAND ${CARGO_EXE} build --release --manifest-path "${NEURA_SWARM_MANIFEST}"
        BYPRODUCTS "${NEURA_SWARM_DLL}"
        COMMENT "Building neura_swarm (Rust)"
        VERBATIM
)

add_dependencies(${BINARY_NAME} neura_swarm_rust)

add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "${NEURA_SWARM_DLL}"
                "$<TARGET_FILE_DIR:${BINARY_NAME}>"
        COMMENT "Copying neura_swarm.dll next to ${BINARY_NAME}"
)
