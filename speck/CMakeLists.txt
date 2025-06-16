cmake_minimum_required(VERSION 3.28.3)
project(specktest C)

set(CMAKE_C_STANDARD 23)

add_executable(specktest genroundkey.c encrypt.c decrypt.c encryption_key_schedule.c)
