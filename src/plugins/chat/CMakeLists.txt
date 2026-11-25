# Generated from MQ2Chat.vcxproj
# This file is designed to work with add_subdirectory()

# ---------------------------------------------------------------------
# Props file includes
# ---------------------------------------------------------------------
include("../../Plugin.cmake")

# ---------------------------------------------------------------------
# Source files
# ---------------------------------------------------------------------
set(MQ2Chat_SOURCES
    "MQ2Chat.cpp"
)

source_groups("Source Files" ${MQ2Chat_SOURCES})

# ---------------------------------------------------------------------
# Target definition
# ---------------------------------------------------------------------
add_library(MQ2Chat SHARED
    ${MQ2Chat_SOURCES}
)

set_target_properties(MQ2Chat PROPERTIES FOLDER "core/plugins")

# ---------------------------------------------------------------------
# Apply props file configurations
# ---------------------------------------------------------------------
target_Plugin_props(MQ2Chat)

# ---------------------------------------------------------------------
# Project dependencies
# ---------------------------------------------------------------------
target_link_libraries(MQ2Chat PRIVATE MQ2Main)

# ============================================================================
# MANUAL CONVERSION NOTES
# ============================================================================
#
# - Review and adjust as needed
