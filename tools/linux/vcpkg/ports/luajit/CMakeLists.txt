cmake_minimum_required(VERSION 3.20)
project(luajit LANGUAGES C)

# Mirrors the "static" path of src/msvcbuild.bat; lj_vm.obj comes from buildvm.
file(GLOB lj_srcs lj_*.c lib_*.c)
add_library(lua51 STATIC ${lj_srcs} "${CMAKE_CURRENT_SOURCE_DIR}/lj_vm.obj")
target_compile_definitions(lua51 PRIVATE _CRT_SECURE_NO_DEPRECATE)
target_compile_options(lua51 PRIVATE /W3 /O2 /Z7)
set_target_properties(lua51 PROPERTIES STATIC_LIBRARY_OPTIONS /nodefaultlib)

add_executable(luajit luajit.c)
target_compile_definitions(luajit PRIVATE _CRT_SECURE_NO_DEPRECATE)
target_link_libraries(luajit PRIVATE lua51)

install(TARGETS lua51 ARCHIVE DESTINATION lib)
install(TARGETS luajit RUNTIME DESTINATION bin)
install(FILES lua.h luajit.h luaconf.h lualib.h lauxlib.h lua.hpp DESTINATION include/luajit)
