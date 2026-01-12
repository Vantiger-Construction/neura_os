# Stub FindPkgConfig module for Windows builds.
#
# The Firebase C++ SDK's top-level CMakeLists unconditionally runs
#   include(FindPkgConfig)
# even though pkg-config is only needed on Unix (guarded by `UNIX`).
#
# On some setups, the Visual Studio-bundled CMake module set can be corrupted,
# causing `include(FindPkgConfig)` to fail before generation.
#
# Providing this stub keeps Windows builds unblocked without affecting Unix.

set(PKG_CONFIG_FOUND FALSE)

function(pkg_check_modules)
  # Intentionally a no-op on Windows.
endfunction()

function(pkg_search_module)
  # Intentionally a no-op on Windows.
endfunction()
