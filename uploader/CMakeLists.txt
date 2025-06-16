cmake_minimum_required(VERSION 3.28)
project(uploader C)

set(CMAKE_C_STANDARD 23)

add_executable(uploader uploader.c ihex.c)

include_directories(${CMAKE_SOURCE_DIR})
