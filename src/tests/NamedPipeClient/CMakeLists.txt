# Generated from NamedPipeClient.vcxproj
# This file is designed to work with add_subdirectory()

# ---------------------------------------------------------------------
# Props file includes
# ---------------------------------------------------------------------
include("../../Common.cmake")

# ---------------------------------------------------------------------
# Header files
# ---------------------------------------------------------------------
set(NamedPipeClient_HEADERS
    "../../routing/NamedPipes.h"
)

source_groups("Header Files" ${NamedPipeClient_HEADERS})

# ---------------------------------------------------------------------
# Source files
# ---------------------------------------------------------------------
set(NamedPipeClient_SOURCES
    "App.cpp"
)

source_groups("Source Files" ${NamedPipeClient_SOURCES})

# ---------------------------------------------------------------------
# Target definition
# ---------------------------------------------------------------------
add_executable(NamedPipeClient
    ${NamedPipeClient_HEADERS}
    ${NamedPipeClient_SOURCES}
)

set_target_properties(NamedPipeClient PROPERTIES FOLDER "core/applications/tests")

# ---------------------------------------------------------------------
# Apply props file configurations
# ---------------------------------------------------------------------
target_Common_props(NamedPipeClient)

# ---------------------------------------------------------------------
# Preprocessor definitions
# ---------------------------------------------------------------------
target_compile_definitions(NamedPipeClient PRIVATE
    "_CRT_SECURE_NO_WARNINGS"
    "WIN32"
    "$<$<CONFIG:Debug>:_DEBUG>"
    "_CONSOLE"
    "$<$<CONFIG:Release>:NDEBUG>"
)

# ---------------------------------------------------------------------
# Include directories
# ---------------------------------------------------------------------
target_include_directories(NamedPipeClient PRIVATE
    "${CMAKE_SOURCE_DIR}/src"
)

# ---------------------------------------------------------------------
# Compiler options
# ---------------------------------------------------------------------
target_compile_options(NamedPipeClient PRIVATE
    "/W3"
    "/permissive-"
    "$<$<CONFIG:Release>:/Gy>"
    "$<$<CONFIG:Release>:/Oi>"
)

# ---------------------------------------------------------------------
# Link libraries
# ---------------------------------------------------------------------
target_link_libraries(NamedPipeClient PRIVATE
    "$<$<CONFIG:Debug>:fmtd.lib>"
    "$<$<CONFIG:Release>:fmt.lib>"
)

# ---------------------------------------------------------------------
# Linker options
# ---------------------------------------------------------------------
target_link_options(NamedPipeClient PRIVATE
    "/DEBUG"
    "/SUBSYSTEM:CONSOLE"
    "$<$<CONFIG:Release>:/OPT:REF>"
    "$<$<CONFIG:Release>:/OPT:ICF>"
)

# ============================================================================
# MANUAL CONVERSION NOTES
# ============================================================================
#
# - Review and adjust as needed
