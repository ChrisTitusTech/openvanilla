# Generated from Actors.vcxproj
# This file is designed to work with add_subdirectory()

# ---------------------------------------------------------------------
# Props file includes
# ---------------------------------------------------------------------
include("../../Common.cmake")

# ---------------------------------------------------------------------
# Source files
# ---------------------------------------------------------------------
set(Actors_SOURCES
    "Main.cpp"
)

source_groups("Source Files" ${Actors_SOURCES})

# ---------------------------------------------------------------------
# Target definition
# ---------------------------------------------------------------------
add_executable(Actors
    ${Actors_SOURCES}
)

set_target_properties(Actors PROPERTIES FOLDER "core/applications/tests")

# ---------------------------------------------------------------------
# Apply props file configurations
# ---------------------------------------------------------------------
target_Common_props(Actors)

# ---------------------------------------------------------------------
# Project dependencies
# ---------------------------------------------------------------------
target_link_libraries(Actors PRIVATE routing)

# ---------------------------------------------------------------------
# Preprocessor definitions
# ---------------------------------------------------------------------
target_compile_definitions(Actors PRIVATE
    "$<$<STREQUAL:${CMAKE_GENERATOR_PLATFORM},Win32>:WIN32>"
    "$<$<CONFIG:Debug>:_DEBUG>"
    "_CONSOLE"
    "MQ2MAIN_IMPL"
    "$<$<CONFIG:Release>:NDEBUG>"
)

# ---------------------------------------------------------------------
# Include directories
# ---------------------------------------------------------------------
target_include_directories(Actors PRIVATE
    "${VCPKG_IncludeStatic}/crashpad"
    "${CMAKE_SOURCE_DIR}/include"
    "${CMAKE_SOURCE_DIR}/src"
)

# ---------------------------------------------------------------------
# Compiler options
# ---------------------------------------------------------------------
target_compile_options(Actors PRIVATE
    "/W3"
    "/permissive-"
    "$<$<CONFIG:Release>:/Gy>"
    "$<$<CONFIG:Release>:/Oi>"
)

# ---------------------------------------------------------------------
# Library directories
# ---------------------------------------------------------------------
target_link_directories(Actors PRIVATE
    "${MQLibDir}"
    "${PlatformLibraryDirectories}"
    "${VCPKG_LibraryDirs}"
    "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/"
)

# ---------------------------------------------------------------------
# Link libraries
# ---------------------------------------------------------------------
target_link_libraries(Actors PRIVATE
    "$<$<CONFIG:Debug>:fmtd.lib>"
    "$<$<STREQUAL:${CMAKE_GENERATOR_PLATFORM},Win32>:d3d11.lib>"
    "$<$<CONFIG:Release>:fmt.lib>"
)

# ---------------------------------------------------------------------
# Linker options
# ---------------------------------------------------------------------
target_link_options(Actors PRIVATE
    "/DEBUG"
    "/SUBSYSTEM:CONSOLE"
    "$<$<CONFIG:Release>:/OPT:REF>"
    "$<$<CONFIG:Release>:/OPT:ICF>"
)

# ---------------------------------------------------------------------
# Character set defines
# ---------------------------------------------------------------------
target_compile_definitions(Actors PRIVATE
    "UNICODE"
    "_UNICODE"
)

# ============================================================================
# MANUAL CONVERSION NOTES
# ============================================================================
#
# - Review and adjust as needed
