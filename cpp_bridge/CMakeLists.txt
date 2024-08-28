cmake_minimum_required(VERSION 2.8.12)


project(bridge)

#set(CMAKE_CXX_COMPILER aarch64-linux-gnu-g++)

include_directories(${PROJECT_SOURCE_DIR}/src)

set(CMAKE_FIND_ROOT_PATH )

if (WIN32)

else ()
    find_package(LLVM REQUIRED CONFIG)
    message(STATUS "Found LLVM ${LLVM_PACKAGE_VERSION}")
    message(STATUS "LLVM_INCLUDE_DIRS: ${LLVM_INCLUDE_DIRS}")
    message(STATUS "LLVM_DEFINITIONS_LIST: ${LLVM_DEFINITIONS_LIST}")
    add_definitions(${LLVM_DEFINITIONS_LIST})
    llvm_map_components_to_libnames(llvm_libs support core irreader)
    message(STATUS "llvm_libs: ${llvm_libs}")

    include_directories(${LLVM_INCLUDE_DIRS})

    #find_package(ZSTD REQUIRED CONFIG)
endif()


add_library(bridge STATIC src/bridge.cpp)

#add_library(bridge_shared SHARED src/bridge.cpp)

#target_link_libraries(bridge_shared ${llvm_libs})

