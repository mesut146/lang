cmake_minimum_required(VERSION 2.8.12)

project(lang)

set(CMAKE_CXX_FLAGS "-std=c++17 -g -pg")

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


