# Fork-only adjustments for the Linux clang-cl/Ninja build (tools/linux/README.md).
# Injected with CMAKE_PROJECT_INCLUDE, so it runs at the end of the root project() call.
include_guard(GLOBAL)

if(CMAKE_GENERATOR MATCHES "Visual Studio")
    return()
endif()

# Project files throughout the tree (including the eqlib submodule) test
# CMAKE_GENERATOR_PLATFORM, which single-config generators cannot set: Ninja rejects it,
# and try_compile forwards it to its test projects. Answer reads from MacroQuest's own
# files with MQ_PLATFORM and leave it unset for CMake modules, vcpkg and try_compile.
function(_mq_linux_platform_scope list_file out_var)
    cmake_path(IS_PREFIX CMAKE_SOURCE_DIR "${list_file}" NORMALIZE in_source)
    cmake_path(IS_PREFIX CMAKE_BINARY_DIR "${list_file}" NORMALIZE in_binary)
    cmake_path(IS_PREFIX MQ_LINUX_VCPKG_DIR "${list_file}" NORMALIZE in_vcpkg)
    if(in_source AND NOT in_binary AND NOT in_vcpkg)
        set(${out_var} "${MQ_PLATFORM}" PARENT_SCOPE)
    else()
        set(${out_var} "" PARENT_SCOPE)
    endif()
endfunction()

macro(_mq_linux_platform_watch variable access value list_file)
    # Macro arguments are text substitutions, not variables, so they must be expanded.
    if("${access}" MATCHES "READ_ACCESS$")
        _mq_linux_platform_scope("${list_file}" _mq_linux_platform)
        if(NOT "${_mq_linux_platform}" STREQUAL "${value}")
            set(CMAKE_GENERATOR_PLATFORM "${_mq_linux_platform}")
        endif()
    endif()
endmacro()

set(MQ_LINUX_VCPKG_DIR "${CMAKE_SOURCE_DIR}/contrib/vcpkg")
variable_watch(CMAKE_GENERATOR_PLATFORM _mq_linux_platform_watch)

# NASM: project files only set VS_TOOL_OVERRIDE "NASM". Target compile options are MSVC
# flags, so leave <FLAGS> out of the NASM command line.
set(CMAKE_ASM_NASM_COMPILE_OBJECT "<CMAKE_ASM_NASM_COMPILER> <DEFINES> <INCLUDES> -f win64 -o <OBJECT> <SOURCE>")
enable_language(ASM_NASM)

# fmt 10.2's FMT_STRING is not a constant expression under current clang (spdlog uses it in
# SPDLOG_LOGGER_CATCH). Without consteval, format strings are checked at run time instead.
add_compile_definitions(FMT_CONSTEVAL=)

# ProtobufLibs.h autolinks abseil and utf8_range for the MSBuild path's newer protobuf. The
# CMake path's protobuf 3.21 has neither, so drop those default libs when they aren't installed.
if(NOT EXISTS "${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/lib/absl_base.lib")
    file(STRINGS "${CMAKE_SOURCE_DIR}/include/mq/contrib/protobuf/ProtobufLibs.h" _mq_linux_autolinks
        REGEX "#pragma comment\\(lib, \"(absl_|utf8_)")
    foreach(_line IN LISTS _mq_linux_autolinks)
        string(REGEX REPLACE ".*\"([^\"]+)\".*" "\\1" _lib "${_line}")
        add_link_options("/NODEFAULTLIB:${_lib}.lib")
    endforeach()
endif()

# Build steps call powershell.exe; an imported target of that name redirects them to pwsh.
if(NOT TARGET powershell.exe)
    add_executable(powershell.exe IMPORTED GLOBAL)
    set_target_properties(powershell.exe PROPERTIES
        IMPORTED_LOCATION "${CMAKE_CURRENT_LIST_DIR}/../bin/powershell.exe")
endif()

# Resolve the "$<$<STREQUAL:a,b>:value>" form used in VS_SETTINGS.
function(_mq_linux_eval_vs_genex input out_var)
    set(value "${input}")
    while(value MATCHES "\\$<\\$<STREQUAL:([^,>]*),([^>]*)>:([^>]*)>")
        if(CMAKE_MATCH_1 STREQUAL CMAKE_MATCH_2)
            set(replacement "${CMAKE_MATCH_3}")
        else()
            set(replacement "")
        endif()
        string(REPLACE "${CMAKE_MATCH_0}" "${replacement}" value "${value}")
    endwhile()
    set(${out_var} "${value}" PARENT_SCOPE)
endfunction()

function(_mq_linux_collect_targets dir out_var)
    get_property(targets DIRECTORY "${dir}" PROPERTY BUILDSYSTEM_TARGETS)
    get_property(subdirs DIRECTORY "${dir}" PROPERTY SUBDIRECTORIES)
    foreach(subdir IN LISTS subdirs)
        _mq_linux_collect_targets("${subdir}" sub_targets)
        list(APPEND targets ${sub_targets})
    endforeach()
    set(${out_var} "${targets}" PARENT_SCOPE)
endfunction()

# Visual Studio's rc.exe accepts UTF-16 resource scripts; clang's preprocessor does not.
# Compile a UTF-8 copy (regenerated on reconfigure) instead, searching the original directory for relative includes.
function(_mq_linux_utf16_rc target source abs_source)
    file(READ "${abs_source}" bom LIMIT 2 HEX)
    if(NOT bom STREQUAL "fffe")
        return()
    endif()
    cmake_path(RELATIVE_PATH abs_source BASE_DIRECTORY "${CMAKE_SOURCE_DIR}" OUTPUT_VARIABLE rel)
    set(utf8 "${CMAKE_BINARY_DIR}/mq-linux-rc/${rel}")
    cmake_path(GET abs_source PARENT_PATH source_dir)
    cmake_path(GET utf8 PARENT_PATH utf8_dir)
    file(MAKE_DIRECTORY "${utf8_dir}")
    execute_process(COMMAND iconv -f UTF-16 -t UTF-8 "${abs_source}"
        OUTPUT_FILE "${utf8}.tmp" RESULT_VARIABLE result)
    if(NOT result EQUAL 0)
        message(FATAL_ERROR "iconv failed to convert ${abs_source}")
    endif()
    # Keep the timestamp when nothing changed so reconfiguring doesn't relink every target.
    file(COPY_FILE "${utf8}.tmp" "${utf8}" ONLY_IF_DIFFERENT)
    file(REMOVE "${utf8}.tmp")
    set_property(DIRECTORY "${CMAKE_SOURCE_DIR}" APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${abs_source}")
    get_target_property(sources ${target} SOURCES)
    list(TRANSFORM sources REPLACE "^${source}$" "${utf8}")
    set_target_properties(${target} PROPERTIES SOURCES "${sources}")
    set_source_files_properties("${utf8}" TARGET_DIRECTORY ${target}
        PROPERTIES INCLUDE_DIRECTORIES "${source_dir}")
endfunction()

# Ninja ignores VS_SETTINGS/VS_TOOL_OVERRIDE; translate the ones MacroQuest uses.
function(mq_linux_apply_vs_settings)
    _mq_linux_collect_targets("${CMAKE_SOURCE_DIR}" targets)
    foreach(target IN LISTS targets)
        get_target_property(type ${target} TYPE)
        if(type STREQUAL "INTERFACE_LIBRARY" OR type STREQUAL "UTILITY")
            continue()
        endif()
        get_target_property(target_dir ${target} SOURCE_DIR)
        get_target_property(sources ${target} SOURCES)
        foreach(source IN LISTS sources)
            if(source MATCHES "^\\$<")
                continue()
            endif()
            cmake_path(ABSOLUTE_PATH source BASE_DIRECTORY "${target_dir}" OUTPUT_VARIABLE abs_source)
            get_source_file_property(settings "${abs_source}" TARGET_DIRECTORY ${target} VS_SETTINGS)
            get_source_file_property(tool "${abs_source}" TARGET_DIRECTORY ${target} VS_TOOL_OVERRIDE)
            if(NOT settings)
                set(settings "")
            endif()
            _mq_linux_eval_vs_genex("${settings}" settings)

            if("ExcludedFromBuild=true" IN_LIST settings)
                set_source_files_properties("${abs_source}" TARGET_DIRECTORY ${target}
                    PROPERTIES HEADER_FILE_ONLY ON)
                continue()
            endif()

            if(abs_source MATCHES "\\.rc$")
                _mq_linux_utf16_rc(${target} "${source}" "${abs_source}")
                continue()
            endif()

            if(abs_source MATCHES "\\.asm$")
                if(NOT tool STREQUAL "NASM")
                    set_source_files_properties("${abs_source}" TARGET_DIRECTORY ${target}
                        PROPERTIES HEADER_FILE_ONLY ON)
                    continue()
                endif()
                set(includes "")
                set(defines "")
                foreach(setting IN LISTS settings)
                    if(setting MATCHES "^IncludePaths=(.*)$")
                        list(APPEND includes "${CMAKE_MATCH_1}")
                    elseif(setting MATCHES "^PreprocessorDefinitions=(.*)$")
                        list(APPEND defines ${CMAKE_MATCH_1})
                    endif()
                endforeach()
                # VS_SETTINGS escapes ';' inside one entry, so the defines may arrive as a single item.
                string(REPLACE "\\;" ";" defines "${defines}")
                list(FILTER defines EXCLUDE REGEX "^$")
                set_source_files_properties("${abs_source}" TARGET_DIRECTORY ${target}
                    PROPERTIES LANGUAGE ASM_NASM
                    INCLUDE_DIRECTORIES "${includes}"
                    COMPILE_DEFINITIONS "${defines}")
            endif()
        endforeach()
    endforeach()
endfunction()

cmake_language(DEFER DIRECTORY "${CMAKE_SOURCE_DIR}" CALL mq_linux_apply_vs_settings)
