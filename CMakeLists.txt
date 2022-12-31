cmake_minimum_required(VERSION 2.8.12)

project(lang)

set(CMAKE_CXX_FLAGS "-std=c++17 -g")
#set(CMAKE_CXX_FLAGS "-I/usr/lib/llvm-10/include -std=c++14 -D_GNU_SOURCE -D__STDC_CONSTANT_MACROS -D__STDC_FORMAT_MACROS -D__STDC_LIMIT_MACROS -DLLVM_DISABLE_ABI_BREAKING_CHECKS_ENFORCING=1")

#set(CMAKE_EXE_LINKER_FLAGS "-L/data/data/com.termux/files/usr/lib")

file(GLOB src src/*.cpp src/parser/*.cpp)

include_directories(${PROJECT_SOURCE_DIR}/src)

add_executable(lang ${src})

if (WIN32)

else ()
    find_package(LLVM REQUIRED CONFIG)
    message(STATUS "Found LLVM ${LLVM_PACKAGE_VERSION}")
    message(STATUS "inc: ${LLVM_INCLUDE_DIRS}")
    include_directories(${LLVM_INCLUDE_DIRS})

    #llvm_map_components_to_libnames(llvm_libs support core irreader)
    #message(STATUS "libs: ${llvm_libs}")

    #target_link_libraries(lang ${llvm_libs})
    target_link_libraries(lang LLVM-13)

    target_link_libraries(lang stdc++fs)
endif()


