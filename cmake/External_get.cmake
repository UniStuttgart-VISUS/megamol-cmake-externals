include(CMakeParseArguments)
include(FetchContent)

#
# Get external from within the source directory.
#
# external_get(<target>
#     SOURCE_DIR <path>)
#
function(external_get TARGET)
  # Parse arguments
  set(ARGS_ONE_VALUE SOURCE_DIR)
  cmake_parse_arguments(args "" "${ARGS_ONE_VALUE}" "" ${ARGN})

  # Check for local version
  external_try_get_property(${TARGET} BUILD_TYPE)
  external_try_get_property(${TARGET} SOURCE_DIR)

  set(AVAILABLE_VERSION)
  if(DEFINED BUILD_TYPE)
    list(APPEND AVAILABLE_VERSION ${BUILD_TYPE})
  endif()
  if(DEFINED SOURCE_DIR)
    list(APPEND AVAILABLE_VERSION ${SOURCE_DIR})
  endif()

  # Check for requested version
  if(NOT args_SOURCE_DIR)
    message(FATAL_ERROR "No path declared as source")
  endif()

  set(args_SOURCE_DIR "${CMAKE_SOURCE_DIR}/externals/${args_SOURCE_DIR}")

  set(MESSAGE "${TARGET}: path '${args_SOURCE_DIR}'")

  set(REQUESTED_VERSION)
  list(APPEND REQUESTED_VERSION ${CMAKE_BUILD_TYPE})
  list(APPEND REQUESTED_VERSION ${args_SOURCE_DIR})

  # Download immediately if necessary
  if(AVAILABLE_VERSION STREQUAL REQUESTED_VERSION)
    message(STATUS "${MESSAGE} -- already available")
  else()
    message(STATUS "${MESSAGE}")

    string(TOLOWER "${TARGET}" lcName)

    # Set cached version
    external_set_property(${TARGET} BUILD_TYPE "${CMAKE_BUILD_TYPE}")

    external_set_typed_property(${TARGET} NEW_VERSION TRUE BOOL)

    # Set source and binary directory
    external_set_property(${TARGET} SOURCE_DIR "${SOURCE_DIR}")
    external_set_property(${TARGET} BINARY_DIR "${CMAKE_BINARY_DIR}/_deps/${lcName}-build")
  endif()
endfunction()
