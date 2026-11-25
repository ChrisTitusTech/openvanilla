cmake_minimum_required(VERSION 3.20)
project(detours LANGUAGES CXX)

# Mirrors the OBJS list and CFLAGS in Detours' src/Makefile.
add_library(detours STATIC
    detours.cpp modules.cpp disasm.cpp image.cpp creatwth.cpp
    disolx86.cpp disolx64.cpp disolia64.cpp disolarm.cpp disolarm64.cpp)
target_compile_definitions(detours PRIVATE WIN32_LEAN_AND_MEAN _WIN32_WINNT=0x501)
target_compile_options(detours PRIVATE /Zl /Gy)

install(TARGETS detours ARCHIVE DESTINATION lib)
install(FILES detours.h detver.h DESTINATION include/detours)
