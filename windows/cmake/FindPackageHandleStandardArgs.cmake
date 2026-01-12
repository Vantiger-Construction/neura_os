# Minimal replacement for CMake's FindPackageHandleStandardArgs module.
#
# Some Windows environments can end up with a corrupted toolchain-bundled copy of
# this module (e.g., via Visual Studio's CMake component), which breaks CMake
# generation for Flutter desktop projects.
#
# This implementation supports the common usage patterns needed by third-party
# CMake "Find*.cmake" modules used by Flutter plugins (e.g., FindGit, FindPkgConfig).

include(CMakeParseArguments)

macro(find_package_handle_standard_args _fp_hsa_name)
  set(_fp_hsa_args ${ARGN})

  set(_fp_hsa_use_new FALSE)
  foreach(_fp_hsa_a IN LISTS _fp_hsa_args)
    if(_fp_hsa_a STREQUAL "REQUIRED_VARS")
      set(_fp_hsa_use_new TRUE)
      break()
    endif()
  endforeach()

  set(_fp_hsa_required_vars "")
  set(_fp_hsa_fail_message "")

  if(_fp_hsa_use_new)
    cmake_parse_arguments(
      _FPHSA
      "HANDLE_COMPONENTS;CONFIG_MODE"
      "VERSION_VAR;FAIL_MESSAGE"
      "REQUIRED_VARS"
      ${_fp_hsa_args}
    )
    set(_fp_hsa_required_vars ${_FPHSA_REQUIRED_VARS})
    set(_fp_hsa_fail_message "${_FPHSA_FAIL_MESSAGE}")
  else()
    # Old signature: find_package_handle_standard_args(<name> <msg> <var...>)
    # We ignore <msg> (often DEFAULT_MSG) and treat the remaining args as REQUIRED vars.
    if(_fp_hsa_args)
      list(REMOVE_AT _fp_hsa_args 0)
    endif()
    set(_fp_hsa_required_vars ${_fp_hsa_args})
  endif()

  set(_fp_hsa_found TRUE)
  foreach(_fp_hsa_var IN LISTS _fp_hsa_required_vars)
    if(NOT DEFINED ${_fp_hsa_var} OR "${${_fp_hsa_var}}" STREQUAL "")
      set(_fp_hsa_found FALSE)
      break()
    endif()
  endforeach()

  set(${_fp_hsa_name}_FOUND ${_fp_hsa_found})

  if(NOT ${_fp_hsa_name}_FOUND)
    if(_fp_hsa_fail_message STREQUAL "")
      set(_fp_hsa_fail_message "Could NOT find ${_fp_hsa_name} (missing: ${_fp_hsa_required_vars})")
    endif()

    # Mirror the usual behavior: if the package was REQUIRED, error out.
    if(DEFINED ${_fp_hsa_name}_FIND_REQUIRED AND ${${_fp_hsa_name}_FIND_REQUIRED})
      message(FATAL_ERROR "${_fp_hsa_fail_message}")
    endif()
  endif()
endmacro()
