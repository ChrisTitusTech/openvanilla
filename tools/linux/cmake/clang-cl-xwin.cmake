# Cross-compile x64 Windows (MSVC ABI) from Linux with clang-cl + xwin.
# Used directly by the Linux preset and chainloaded by the vcpkg triplet.
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_VERSION 10.0)
set(CMAKE_SYSTEM_PROCESSOR AMD64)

if(DEFINED ENV{XWIN_ROOT})
    set(XWIN_ROOT "$ENV{XWIN_ROOT}")
else()
    set(XWIN_ROOT "$ENV{HOME}/.local/share/xwin")
endif()
set(XWIN_SDK_VERSION 10.0.26100)

set(CMAKE_C_COMPILER clang-cl)
set(CMAKE_CXX_COMPILER clang-cl)
set(CMAKE_LINKER lld-link)
set(CMAKE_AR llvm-lib)
set(CMAKE_RC_COMPILER llvm-rc)
set(CMAKE_MT llvm-mt)
set(CMAKE_ASM_NASM_COMPILER nasm)

set(_target "--target=x86_64-pc-windows-msvc /winsysroot ${XWIN_ROOT}")
set(CMAKE_C_FLAGS_INIT "${_target}")
set(CMAKE_CXX_FLAGS_INIT "${_target}")
foreach(kind EXE SHARED MODULE)
    set(CMAKE_${kind}_LINKER_FLAGS_INIT "/winsysroot:${XWIN_ROOT}")
endforeach()

# "winsdk" is a space-free symlink to "Windows Kits/10"; cmake_llvm_rc does not handle quoted paths.
set(_sdkinc "${XWIN_ROOT}/winsdk/Include/${XWIN_SDK_VERSION}")
file(GLOB _vcinc "${XWIN_ROOT}/VC/Tools/MSVC/*/include")
set(CMAKE_RC_FLAGS_INIT "/I ${_sdkinc}/um /I ${_sdkinc}/shared /I ${_sdkinc}/ucrt /I ${_vcinc}")

set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
# Projects with CMP0091 OLD (cmake_minimum_required < 3.15) ignore CMAKE_MSVC_RUNTIME_LIBRARY and
# default to /MD. vcpkg's own windows.cmake pins the flags in the cache; do the same when chainloaded.
foreach(_lang C CXX)
    set(CMAKE_${_lang}_FLAGS_RELEASE "/MT /O2 /Ob2 /DNDEBUG" CACHE STRING "")
    set(CMAKE_${_lang}_FLAGS_DEBUG "/MTd /Zi /Ob0 /Od /RTC1" CACHE STRING "")
endforeach()
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_TRY_COMPILE_CONFIGURATION Release)

# Case shims for submodule includes whose case differs from the real file (tools/linux/README.md).
get_filename_component(_mq_case_shims "${CMAKE_CURRENT_LIST_DIR}/../case-shims" ABSOLUTE)
string(APPEND CMAKE_CXX_FLAGS_INIT " /I${_mq_case_shims}")
