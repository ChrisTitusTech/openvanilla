# Linux cross-build replacement for contrib/vcpkg-overlays/cmake/luajit.
# Mirrors src/msvcbuild.bat "static": host tools (minilua, buildvm) are built with
# the Linux host compiler for an x64 Windows target, then the library is built
# with the chainloaded clang-cl toolchain (tools/linux/README.md).
vcpkg_check_linkage(ONLY_STATIC_LIBRARY)

set(MQ_UPSTREAM_PORT "${CMAKE_CURRENT_LIST_DIR}/../../../../../contrib/vcpkg-overlays/cmake/luajit")

vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO LuaJIT/LuaJIT
    REF e826d0c101d750fac8334d71e221c50d8dbe236c
    SHA512 d53334e00603fbfef558111e12d5cda50271e22b2ba3dc29e7084ee5b5d38f83a2378d2d6b3da4311d7591209f15a5b56bea9025f62568cb0904c6ef3ee40176
    HEAD_REF v2.1
    PATCHES
        "${MQ_UPSTREAM_PORT}/msvcbuild.patch"
        "${MQ_UPSTREAM_PORT}/003-do-not-set-macosx-deployment-target.patch"
        "${MQ_UPSTREAM_PORT}/mq-debug-release-options.patch"
)

find_program(HOST_CC NAMES cc gcc clang REQUIRED)
set(src "${SOURCE_PATH}/src")
set(host "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-host")
file(MAKE_DIRECTORY "${host}")
set(ALL_LIB lib_base.c lib_math.c lib_bit.c lib_string.c lib_table.c lib_io.c lib_os.c
    lib_package.c lib_debug.c lib_jit.c lib_ffi.c lib_buffer.c)

function(lj_run name)
    vcpkg_execute_required_process(COMMAND ${ARGN} WORKING_DIRECTORY "${src}" LOGNAME "${name}-${TARGET_TRIPLET}")
endfunction()

lj_run(minilua "${HOST_CC}" -O2 -o "${host}/minilua" host/minilua.c -lm)
lj_run(dynasm "${host}/minilua" ../dynasm/dynasm.lua -LN -D WIN -D JIT -D FFI -D ENDIAN_LE -D FPU -D P64
    -o host/buildvm_arch.h vm_x64.dasc)
file(COPY "${SOURCE_PATH}/.relver" DESTINATION "${src}")
file(RENAME "${src}/.relver" "${src}/luajit_relver.txt")
lj_run(genversion "${host}/minilua" host/genversion.lua)

file(GLOB buildvm_srcs "${src}/host/buildvm*.c")
lj_run(buildvm "${HOST_CC}" -O2 -I. -I../dynasm
    -DLUAJIT_TARGET=LUAJIT_ARCH_X64 -DLUAJIT_OS=LUAJIT_OS_WINDOWS
    -o "${host}/buildvm" ${buildvm_srcs})

lj_run(peobj "${host}/buildvm" -m peobj -o lj_vm.obj)
lj_run(bcdef "${host}/buildvm" -m bcdef -o lj_bcdef.h ${ALL_LIB})
lj_run(ffdef "${host}/buildvm" -m ffdef -o lj_ffdef.h ${ALL_LIB})
lj_run(libdef "${host}/buildvm" -m libdef -o lj_libdef.h ${ALL_LIB})
lj_run(recdef "${host}/buildvm" -m recdef -o lj_recdef.h ${ALL_LIB})
lj_run(vmdef "${host}/buildvm" -m vmdef -o jit/vmdef.lua ${ALL_LIB})
lj_run(folddef "${host}/buildvm" -m folddef -o lj_folddef.h lj_opt_fold.c)

file(COPY "${CMAKE_CURRENT_LIST_DIR}/CMakeLists.txt" DESTINATION "${src}")
vcpkg_cmake_configure(SOURCE_PATH "${src}")
vcpkg_cmake_install()

file(INSTALL "${MQ_UPSTREAM_PORT}/luajit.pc" DESTINATION "${CURRENT_PACKAGES_DIR}/lib/pkgconfig")
vcpkg_fixup_pkgconfig()

vcpkg_copy_tools(TOOL_NAMES luajit AUTO_CLEAN)

include(CMakePackageConfigHelpers)
configure_package_config_file(
    "${MQ_UPSTREAM_PORT}/luajit-config.cmake.in"
    "${CURRENT_PACKAGES_DIR}/share/${PORT}/luajit-config.cmake"
    INSTALL_DESTINATION "share/${PORT}"
)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYRIGHT")
