cmake_minimum_required(VERSION 3.10.2)

project("rnnoise_flutter")

# RNNoise library sources
add_library(rnnoise STATIC
    denoise.c
    celt_lpc.c
    kiss_fft.c
    pitch.c
    rnn.c
    rnn_data.c
    rnn_reader.c
)

# Set compile definitions for RNNoise
target_compile_definitions(rnnoise PRIVATE
    HAVE_CONFIG_H=1
    RNNOISE_BUILD=1
    FLOAT_APPROX=1
)

# JNI wrapper for Flutter
add_library(rnnoise_flutter SHARED
    rnnoise_flutter_jni.cpp
)

# Include directories
target_include_directories(rnnoise_flutter PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
)

target_include_directories(rnnoise PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
)

# Link libraries
target_link_libraries(rnnoise_flutter
    rnnoise
    android
    log
)

# Compiler-specific options for optimization
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    target_compile_options(rnnoise PRIVATE
        -O3
        -ffast-math
    )
    target_compile_options(rnnoise_flutter PRIVATE
        -O3
        -ffast-math
    )
endif()