# Linux cross-build stub for crashpad (ANSWERS.md Q-023, tools/linux/README.md).
# Upstream crashpad needs gn + mini_chromium's Windows-only toolchain helpers.
# CrashReportDatabase::Initialize returns null, so MacroQuest disables crash reporting.
set(VCPKG_POLICY_EMPTY_PACKAGE enabled)
set(VCPKG_POLICY_HEADER_ONLY enabled)
file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/include/" DESTINATION "${CURRENT_PACKAGES_DIR}/include/crashpad")
file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/crashpadConfig.cmake" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
file(WRITE "${CURRENT_PACKAGES_DIR}/share/${PORT}/copyright" "Stub headers written for the openvanilla Linux build; no crashpad code is included.\n")
