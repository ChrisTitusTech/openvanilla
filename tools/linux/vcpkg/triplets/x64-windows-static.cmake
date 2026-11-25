# Linux cross-build triplet: same name as the stock triplet so the root CMakeLists.txt
# triplet selection is unchanged; release-only because xwin ships no debug CRT.
set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE static)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_BUILD_TYPE release)
set(VCPKG_CHAINLOAD_TOOLCHAIN_FILE "${CMAKE_CURRENT_LIST_DIR}/../../cmake/clang-cl-xwin.cmake")
set(VCPKG_ENV_PASSTHROUGH XWIN_ROOT)
