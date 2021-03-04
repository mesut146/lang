cmake_minimum_required (VERSION 2.8)

project(lang)

set(CMAKE_CXX_FLAGS "-std=c++11 -g")

file(GLOB src
  src/*.cpp
)

include_directories(
  ${PROJECT_SOURCE_DIR}/src
)

add_executable(lang ${src})
