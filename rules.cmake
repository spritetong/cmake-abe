# * @file       rules.cmake
# * @brief      This file contains common rules to build cmake targets.
# * @details    This file is the part of the cmake-abe library
# *             (https://github.com/spritetong/cmake-abe),
# *             which is licensed under the MIT license
# *             (https://opensource.org/licenses/MIT).
# *             Copyright (C) 2022 spritetong@gmail.com.
# * @author     spritetong@gmail.com
# * @date       2022
# * @version    1.0, 7/9/2022, Tong
# *             - Initial revision.
# *

if(NOT DEFINED _CMKABE_RULES_INITIALIZED)

include("${CMAKE_CURRENT_LIST_DIR}/targets.cmake")

if(NOT DEFINED CMAKE_BUILD_TYPE)
    # Build for Debug by default
    set(CMAKE_BUILD_TYPE "Debug")
endif()
set(CMAKE_BUILD_TYPE "${CMAKE_BUILD_TYPE}" CACHE STRING
    "The build type, typical values defined in CMAKE_CONFIGURATION_TYPES." FORCE)

if(NOT DEFINED TARGET_PREFIX)
    if(NOT "$ENV{CMAKE_TARGET_PREFIX}" STREQUAL "")
        set(TARGET_PREFIX "$ENV{CMAKE_TARGET_PREFIX}")
    else()
        set(TARGET_PREFIX "${CMAKE_SOURCE_DIR}/build/output")
    endif()
endif()

if(NOT DEFINED TARGET_COMMON_INCLUDE_DIR)
    if(IS_DIRECTORY "${TARGET_PREFIX}/include")
        set(TARGET_COMMON_INCLUDE_DIR "${TARGET_PREFIX}/include")
    elseif(IS_DIRECTORY "${TARGET_PREFIX}/common/include")
        set(TARGET_COMMON_INCLUDE_DIR "${TARGET_PREFIX}/common/include")
    elseif(IS_DIRECTORY "${TARGET_PREFIX}/public/include")
        set(TARGET_COMMON_INCLUDE_DIR "${TARGET_PREFIX}/public/include")
    elseif(IS_DIRECTORY "${TARGET_PREFIX}/share/include")
        set(TARGET_COMMON_INCLUDE_DIR "${TARGET_PREFIX}/share/include")
    endif()
endif()

if(NOT DEFINED TARGET_INCLUDE_DIR)
    set(TARGET_INCLUDE_DIR "${TARGET_PREFIX}/${TARGET_TRIPLE}/include")
endif()

if(NOT DEFINED TARGET_LIB_DIR)
    set(TARGET_LIB_DIR "${TARGET_PREFIX}/${TARGET_TRIPLE}/lib")
endif()

if(NOT DEFINED TARGET_BIN_DIR)
    set(TARGET_BIN_DIR "${TARGET_PREFIX}/${TARGET_TRIPLE}/bin")
endif()

if(NOT DEFINED TARGET_OUTPUT_REDIRECT)
    set(TARGET_OUTPUT_REDIRECT ON)
endif()

if(NOT DEFINED TARGET_STRIP_ON_RELEASE)
    set(TARGET_STRIP_ON_RELEASE ON)
endif()

if(NOT DEFINED TARGET_CC_PIC)
    set(TARGET_CC_PIC ON)
endif()

if(NOT DEFINED TARGET_CC_VISIBILITY_HIDDEN)
    set(TARGET_CC_VISIBILITY_HIDDEN ON)
endif()

if(NOT DEFINED TARGET_CC_NO_DELETE_NULL_POINTER_CHECKS)
    set(TARGET_CC_NO_DELETE_NULL_POINTER_CHECKS ON)
endif()

if(NOT DEFINED TARGET_MSVC_AFXDLL)
    set(TARGET_MSVC_AFXDLL ON)
endif()

if(NOT DEFINED TARGET_MSVC_UNICODE)
    set(TARGET_MSVC_UNICODE ON)
endif()

if(NOT DEFINED TARGET_MSVC_UTF8)
    set(TARGET_MSVC_UTF8 ON)
endif()

# ==============================================================================

if(NOT "${PROJECT_NAME}" STREQUAL "")
    message(FATAL_ERROR "Can not define any project before `include <cmake-abe>/rules.cmake`.")
endif()
# Define a dummy project.
project(CMKABE)

include(CheckCCompilerFlag)
check_c_compiler_flag("-s" CC_SUPPORT_STRIP)
check_c_compiler_flag("-fPIC" CC_SUPPORT_PIC)
check_c_compiler_flag("-fvisibility=hidden" CC_SUPPORT_VISIBILITY)
check_c_compiler_flag("-fno-delete-null-pointer-checks" CC_SUPPORT_NO_DELETE_NULL_POINTER_CHECKS)

# Redirect the output directorires to the target directories.
if(TARGET_OUTPUT_REDIRECT)
    set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${TARGET_LIB_DIR}$<LOWER_CASE:>")
    set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${TARGET_LIB_DIR}$<LOWER_CASE:>")
    set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${TARGET_BIN_DIR}$<LOWER_CASE:>")
endif()

if(TARGET_STRIP_ON_RELEASE AND CC_SUPPORT_STRIP)
    if(NOT CMAKE_C_FLAGS_RELEASE MATCHES " -s( |$)")
        # Strip debug info for Release
        set(CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} -s" CACHE STRING
            "Flags used by the C compiler during RELEASE builds." FORCE)
        set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -s" CACHE STRING
            "Flags used by the CXX compiler during RELEASE builds." FORCE)
        set(CMAKE_C_FLAGS_MINSIZEREL "${CMAKE_C_FLAGS_MINSIZEREL} -s" CACHE STRING
            "Flags used by the C compiler during MINSIZEREL builds." FORCE)
        set(CMAKE_CXX_FLAGS_MINSIZEREL "${CMAKE_CXX_FLAGS_MINSIZEREL} -s" CACHE STRING
            "Flags used by the CXX compiler during MINSIZEREL builds." FORCE)
    endif()
endif()

if(NOT CMAKE_C_FLAGS_DEBUG MATCHES " -D_DEBUG( |$)")
    set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} -D_DEBUG" CACHE STRING
        "Flags used by the C compiler during DEBUG builds." FORCE)
    set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} -D_DEBUG" CACHE STRING
        "Flags used by the CXX compiler during DEBUG builds." FORCE)
endif()

if(TARGET_CC_PIC AND CC_SUPPORT_PIC)
    add_compile_options("-fPIC")
endif()

if(TARGET_CC_VISIBILITY_HIDDEN AND CC_SUPPORT_VISIBILITY)
    add_compile_options("-fvisibility=hidden")
endif()

if(TARGET_CC_NO_DELETE_NULL_POINTER_CHECKS AND CC_SUPPORT_NO_DELETE_NULL_POINTER_CHECKS)
    add_compile_options("-fno-delete-null-pointer-checks")
endif()

if(TARGET_MSVC_AFXDLL AND MSVC)
    add_compile_definitions("_AFXDLL")
endif()

if(TARGET_MSVC_UNICODE AND MSVC)
    add_compile_definitions("_UNICODE")
endif()

if(TARGET_MSVC_UTF8 AND MSVC)
    add_compile_options("/utf-8")
endif()

if(NOT "${TARGET_COMMON_INCLUDE_DIR}" STREQUAL "")
    include_directories(BEFORE SYSTEM "${TARGET_COMMON_INCLUDE_DIR}")
endif()
include_directories(BEFORE SYSTEM "${TARGET_INCLUDE_DIR}")
link_directories(BEFORE "${TARGET_LIB_DIR}")

# pkg-config
string(REGEX MATCHALL "[^${CMKABE_PS}]+" _l "$ENV{PKG_CONFIG_PATH_${TARGET_TRIPLE}}${CMKABE_PS}$ENV{PKG_CONFIG_PATH_${TARGET_TRIPLE_UNDERSCORE}}${CMKABE_PS}$ENV{PKG_CONFIG_PATH}")
list(REMOVE_ITEM _l "")
set(_s "${TARGET_PREFIX}/${TARGET_TRIPLE}/lib/pkgconfig")
if (NOT _s IN_LIST _l)
    list(INSERT _l 0 "${_s}")
endif()
string(JOIN "${CMKABE_PS}" _s ${_l})
set(ENV{PKG_CONFIG_PATH} "${_s}")

# CARGO_WORKSPACE_DIR
if(NOT DEFINED CARGO_WORKSPACE_DIR)
    if (NOT "$ENV{CARGO_WORKSPACE_DIR}" STREQUAL "")
        set(_s "$ENV{CARGO_WORKSPACE_DIR}")
    else()
        cmkabe_find_in_ancesters("${CMAKE_SOURCE_DIR}" "cargo.toml" _s)
        if(_s)
            get_filename_component(_s "${_s}" DIRECTORY)
        else()
            set(_s "${CMAKE_SOURCE_DIR}")
        endif()
    endif()
    set(CARGO_WORKSPACE_DIR "${_s}" CACHE INTERNAL "" FORCE)
endif()

# CARGO_TARGET_OUT_DIR
if(TARGET_TRIPLE STREQUAL "${HOST_TRIPLE}")
    set(_s "")
else()
    set(_s "${TARGET_TRIPLE}/")
endif()
if(CMAKE_BUILD_TYPE MATCHES "^(Debug|debug)$")
    set(_s "${_s}debug") 
else()
    set(_s "${_s}release")
endif()
set(CARGO_TARGET_OUT_DIR "${CARGO_WORKSPACE_DIR}/target/${_s}")

set(_CMKABE_RULES_INITIALIZED ON)
endif()
