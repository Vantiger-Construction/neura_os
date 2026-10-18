cmake_minimum_required(VERSION 3.14)
project(neura_windows_tts_check LANGUAGES CXX)
enable_testing()
add_executable(neura_tts_lifecycle_check "lifecycle_test.cpp")
target_compile_features(neura_tts_lifecycle_check PRIVATE cxx_std_17)
add_test(NAME neura_tts_lifecycle_check COMMAND neura_tts_lifecycle_check)
if(MSVC)
  target_compile_options(neura_tts_lifecycle_check PRIVATE /W4 /WX /EHsc)
else()
  target_compile_options(neura_tts_lifecycle_check PRIVATE -Wall -Wextra -Werror -pedantic)
endif()
if(WIN32)
  if(NOT EXISTS "${FLUTTER_WRAPPER_INCLUDE}/flutter/method_channel.h")
    message(FATAL_ERROR "Provide the genuine Flutter Windows wrapper include directory")
  endif()
  add_library(neura_windows_tts_check OBJECT "../../windows/runner/neura_windows_tts.cpp")
  target_include_directories(neura_windows_tts_check PRIVATE "${FLUTTER_WRAPPER_INCLUDE}")
  target_compile_features(neura_windows_tts_check PRIVATE cxx_std_20)
  target_compile_definitions(neura_windows_tts_check PRIVATE NOMINMAX)
  if(MSVC)
    target_compile_options(neura_windows_tts_check PRIVATE /W4 /WX /EHsc)
  endif()
  get_filename_component(FLUTTER_WRAPPER_SOURCE "${FLUTTER_WRAPPER_INCLUDE}" DIRECTORY)
  if(NOT EXISTS "${FLUTTER_WRAPPER_SOURCE}/standard_codec.cc")
    message(FATAL_ERROR "Provide the genuine Flutter wrapper sources beside its include directory")
  endif()
  if(NOT EXISTS "${FLUTTER_ENGINE_INCLUDE}/flutter_messenger.h" OR
     NOT EXISTS "${FLUTTER_ENGINE_LIBRARY}" OR NOT EXISTS "${FLUTTER_ENGINE_DLL}")
    message(FATAL_ERROR "Provide the genuine Flutter engine headers, import library and DLL")
  endif()
  # Link the actual owner against SAPI and Flutter's codec, but execute only
  # lifecycle_test.cpp's pure state/string checks. No voice is instantiated.
  target_sources(neura_tts_lifecycle_check PRIVATE
    $<TARGET_OBJECTS:neura_windows_tts_check>
    "${FLUTTER_WRAPPER_SOURCE}/standard_codec.cc"
    "${FLUTTER_WRAPPER_SOURCE}/core_implementations.cc")
  target_include_directories(neura_tts_lifecycle_check PRIVATE
    "${FLUTTER_WRAPPER_INCLUDE}" "${FLUTTER_ENGINE_INCLUDE}")
  target_link_libraries(neura_tts_lifecycle_check PRIVATE sapi ole32 "${FLUTTER_ENGINE_LIBRARY}")
  add_custom_command(TARGET neura_tts_lifecycle_check POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${FLUTTER_ENGINE_DLL}"
      "$<TARGET_FILE_DIR:neura_tts_lifecycle_check>")
endif()
