cmake_minimum_required(VERSION 2.8.12)

project(lang)

set(CMAKE_CXX_FLAGS "-std=c++14 -g")
#set(CMAKE_CXX_FLAGS "-I/usr/lib/llvm-10/include -std=c++14 -D_GNU_SOURCE -D__STDC_CONSTANT_MACROS -D__STDC_FORMAT_MACROS -D__STDC_LIMIT_MACROS -DLLVM_DISABLE_ABI_BREAKING_CHECKS_ENFORCING=1")

set(CMAKE_EXE_LINKER_FLAGS "-L/data/data/com.termux/files/usr/lib")

file(GLOB src src/*.cpp src/parser/*.cpp)

include_directories(${PROJECT_SOURCE_DIR}/src)

#find_package(LLVM)

add_executable(lang ${src})
