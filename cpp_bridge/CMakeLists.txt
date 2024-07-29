cmake_minimum_required(VERSION 2.8.12)

project(bridge)

set(CMAKE_CXX_FLAGS "-std=c++2a -g -fstack-protector-all")

include_directories(${PROJECT_SOURCE_DIR}/src)


if (WIN32)

else ()
    find_package(LLVM REQUIRED CONFIG)
    message(STATUS "Found LLVM ${LLVM_PACKAGE_VERSION}")
    message(STATUS "inc: ${LLVM_INCLUDE_DIRS}")

    include_directories(${LLVM_INCLUDE_DIRS})
    #target_link_libraries(lang LLVM-16)
    #target_link_libraries(lang stdc++fs)
endif()


add_library(bridge STATIC src/bridge.cpp)


