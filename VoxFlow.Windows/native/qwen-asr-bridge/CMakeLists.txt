cmake_minimum_required(VERSION 3.25)

project(vf_qwen_asr_bridge LANGUAGES C CXX)

if(NOT MSVC)
    message(FATAL_ERROR "The VoxFlow Qwen bridge is a Windows x64 MSVC target.")
endif()

option(VF_QWEN_TEST_BACKEND "Build the deterministic native contract backend" OFF)
set(VF_QWEN_UPSTREAM_DIR "" CACHE PATH "Clean checkout of the pinned antirez/qwen-asr revision")

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

add_library(qwen_asr SHARED
    src/vf_qwen_bridge.cpp
)

target_include_directories(qwen_asr
    PUBLIC include
)
target_compile_definitions(qwen_asr PRIVATE VF_QWEN_BRIDGE_EXPORTS)
target_compile_options(qwen_asr PRIVATE
    /utf-8
    /W4
    /WX
    $<$<COMPILE_LANGUAGE:CXX>:/permissive->
)
target_link_options(qwen_asr PRIVATE /INCREMENTAL:NO)
set_target_properties(qwen_asr PROPERTIES OUTPUT_NAME qwen_asr)

if(VF_QWEN_TEST_BACKEND)
    target_compile_definitions(qwen_asr PRIVATE VF_QWEN_TEST_BACKEND)
else()
    if(NOT EXISTS "${VF_QWEN_UPSTREAM_DIR}/qwen_asr.h")
        message(FATAL_ERROR "VF_QWEN_UPSTREAM_DIR must point to the pinned clean qwen-asr checkout.")
    endif()

    set(VF_QWEN_WINDOWS_PORT_DIR "${CMAKE_CURRENT_LIST_DIR}/../qwen-asr/windows-port")
    target_include_directories(qwen_asr PRIVATE
        "${VF_QWEN_WINDOWS_PORT_DIR}/include"
        "${VF_QWEN_UPSTREAM_DIR}"
    )
    target_compile_options(qwen_asr PRIVATE /FIwindows-msvc.h)
    target_sources(qwen_asr PRIVATE
        "${VF_QWEN_UPSTREAM_DIR}/qwen_asr.c"
        "${VF_QWEN_UPSTREAM_DIR}/qwen_asr_kernels.c"
        "${VF_QWEN_UPSTREAM_DIR}/qwen_asr_kernels_generic.c"
        "${VF_QWEN_UPSTREAM_DIR}/qwen_asr_kernels_neon.c"
        "${VF_QWEN_UPSTREAM_DIR}/qwen_asr_kernels_avx.c"
        "${VF_QWEN_UPSTREAM_DIR}/qwen_asr_audio.c"
        "${VF_QWEN_UPSTREAM_DIR}/qwen_asr_encoder.c"
        "${VF_QWEN_UPSTREAM_DIR}/qwen_asr_decoder.c"
        "${VF_QWEN_UPSTREAM_DIR}/qwen_asr_tokenizer.c"
        "${VF_QWEN_UPSTREAM_DIR}/qwen_asr_safetensors.c"
        "${VF_QWEN_WINDOWS_PORT_DIR}/src/windows_compat.c"
    )
endif()

include(CTest)
if(BUILD_TESTING AND VF_QWEN_TEST_BACKEND)
    add_executable(vf_qwen_native_contract tests/native_contract.c)
    target_link_libraries(vf_qwen_native_contract PRIVATE qwen_asr)
    target_compile_options(vf_qwen_native_contract PRIVATE /utf-8 /W4 /WX)
    add_test(NAME vf_qwen_native_contract COMMAND vf_qwen_native_contract)
endif()
