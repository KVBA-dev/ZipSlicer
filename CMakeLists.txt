cmake_minimum_required(VERSION 3.10)
project(ZipSlicer)
set(CMAKE_CXX_STANDARD 17)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/bin)

add_executable(ZipSlicer
        main.cpp
        Slicer.h
        Exceptions.h
        SystemUtility.h
)

if (MINGW)
    target_link_options(ZipSlicer PRIVATE -static -static-libgcc -static-libstdc++)
endif()

set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -O3")
