include(CMakeParseArguments)
include(GNUInstallDirs)

set(EXTERNAL_SCRIPTS_DIR "${CMAKE_CURRENT_LIST_DIR}")

include("${EXTERNAL_SCRIPTS_DIR}/External_arguments.cmake")
include("${EXTERNAL_SCRIPTS_DIR}/External_properties.cmake")
include("${EXTERNAL_SCRIPTS_DIR}/External_download.cmake")
include("${EXTERNAL_SCRIPTS_DIR}/External_get.cmake")

#
# Adds an external header-only project.
#
# add_external_headeronly_project(<target>
#     DEPENDS <other targets>
#     GIT_REPOSITORY <git url> [GIT_TAG <tag or commit>] [GIT_CONFIG <config>] | URL <zip url> [URL_HASH <file hash>] | SOURCE_DIR <source path>
#     INCLUDE_DIR <include directories relative to the source directory
#                  - omit for the source directory itself>)
#
function(add_external_headeronly_project TARGET)
  # Parse arguments
  set(ARGS_ONE_VALUE GIT_REPOSITORY GIT_TAG GIT_CONFIG URL URL_HASH SOURCE_DIR)
  set(ARGS_MULT_VALUES INCLUDE_DIR DEPENDS)
  cmake_parse_arguments(args "" "${ARGS_ONE_VALUE}" "${ARGS_MULT_VALUES}" ${ARGN})

  # Download or get it from a local path
  if(args_GIT_REPOSITORY)
    external_download(${TARGET} GIT_REPOSITORY ${args_GIT_REPOSITORY} GIT_TAG ${args_GIT_TAG} GIT_CONFIG ${args_GIT_CONFIG})
  elseif(args_URL)
    external_download(${TARGET} URL ${args_URL} URL_HASH ${args_URL_HASH})
  elseif(args_SOURCE_DIR)
    external_get(${TARGET} SOURCE_DIR ${args_SOURCE_DIR})
  else()
    message(FATAL_ERROR "No path or git repository declared as source")
  endif()

  # Create interface library
  add_library(${TARGET} INTERFACE)

  # Add include directories
  external_get_property(${TARGET} SOURCE_DIR)

  if(args_INCLUDE_DIR)
    set(INCLUDE_DIRS)
    foreach(INCLUDE_DIR IN LISTS args_INCLUDE_DIR)
      if(EXISTS "${SOURCE_DIR}/${INCLUDE_DIR}")
        list(APPEND INCLUDE_DIRS "${SOURCE_DIR}/${INCLUDE_DIR}")
      else()
        message(WARNING "Include directory '${SOURCE_DIR}/${INCLUDE_DIR}' not found. Adding path '${INCLUDE_DIR}' instead.")
        list(APPEND INCLUDE_DIRS "${INCLUDE_DIR}")
      endif()
    endforeach()
  else()
    set(INCLUDE_DIRS "${SOURCE_DIR}")
  endif()

  target_include_directories(${TARGET} SYSTEM INTERFACE ${INCLUDE_DIRS})

  # Add dependencies
  if(args_DEPENDS)
    add_dependencies(${TARGET} ${args_DEPENDS})
  endif()

  # Remove unused variable
  external_unset_property(${TARGET} NEW_VERSION)
endfunction(add_external_headeronly_project)





#
# Adds an external project.
#
# add_external_project(<target> [SHARED]
#     DEPENDS <other targets>
#     GIT_REPOSITORY <git url> [GIT_TAG <tag or commit>] [GIT_CONFIG <config>] | URL <zip url> [URL_HASH <file hash>] | SOURCE_DIR <source path>
#     PATCH_COMMAND <command>
#     DEBUG_SUFFIX <suffix>
#     RELWITHDEBINFO_SUFFIX <suffix>
#     BUILD_BYPRODUCTS <output library files>
#     CMAKE_ARGS <additional arguments>
#     FOLDER_NAME <folder name>
#     SOURCE_SUBDIR <subdirectory with CMakeLists.txt>)
#
function(add_external_project TARGET)
  set(ARGS_OPTIONS SHARED)
  set(ARGS_ONE_VALUE GIT_REPOSITORY GIT_TAG GIT_CONFIG URL URL_HASH SOURCE_DIR DEBUG_SUFFIX RELWITHDEBINFO_SUFFIX FOLDER_NAME SOURCE_SUBDIR)
  set(ARGS_MULT_VALUES CMAKE_ARGS PATCH_COMMAND DEPENDS COMMANDS BUILD_BYPRODUCTS)
  cmake_parse_arguments(args "${ARGS_OPTIONS}" "${ARGS_ONE_VALUE}" "${ARGS_MULT_VALUES}" ${ARGN})

  _argument_default(COMMANDS "")
  _argument_default(FOLDER_NAME "external")

  # Download or get it from a local path
  if(args_GIT_REPOSITORY)
    if(args_SOURCE_SUBDIR)
      external_download(${TARGET} GIT_REPOSITORY ${args_GIT_REPOSITORY} GIT_TAG ${args_GIT_TAG} GIT_CONFIG ${args_GIT_CONFIG} SOURCE_SUBDIR ${args_SOURCE_SUBDIR})
    else()
      external_download(${TARGET} GIT_REPOSITORY ${args_GIT_REPOSITORY} GIT_TAG ${args_GIT_TAG} GIT_CONFIG ${args_GIT_CONFIG})
    endif()
  elseif(args_URL)
      if(args_SOURCE_SUBDIR)
        external_download(${TARGET} URL ${args_URL} URL_HASH ${args_URL_HASH} SOURCE_SUBDIR ${args_SOURCE_SUBDIR})
      else()
        external_download(${TARGET} URL ${args_URL} URL_HASH ${args_URL_HASH})
      endif()
  elseif(args_SOURCE_DIR)
    external_get(${TARGET} SOURCE_DIR ${args_SOURCE_DIR})
  else()
    message(FATAL_ERROR "No path or git repository declared as source")
  endif()

  external_get_property(${TARGET} NEW_VERSION)

  # Get and set directories
  external_get_property(${TARGET} SOURCE_DIR)
  external_get_property(${TARGET} BINARY_DIR)

  string(REGEX REPLACE "\-build(/$|$)" "\-install" INSTALL_DIR "${BINARY_DIR}")
  external_set_property(${TARGET} INSTALL_DIR "${INSTALL_DIR}")
  external_set_property(${TARGET} CONFIG_DIR "${INSTALL_DIR}")

  # Get available configurations on multi-config systems,
  # or the used configuration otherwise
  get_property(MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)

  if(args_SHARED)
    set(CONFIG Release)
  elseif(MULTICONFIG)
    set(CONFIG Release)
  else()
    set(CONFIG ${CMAKE_BUILD_TYPE})
  endif()

  # Configure
  if(NEW_VERSION)
    # Apply patch
    if(args_PATCH_COMMAND)
      string(REPLACE "<SOURCE_DIR>" "${SOURCE_DIR}" PATCH_COMMAND "${args_PATCH_COMMAND}")

      execute_process(COMMAND ${PATCH_COMMAND} RESULT_VARIABLE PATCH_RESULT)

      if(NOT "${PATCH_RESULT}" STREQUAL "0")
        message(FATAL_ERROR "Fatal error while applying patch for target ${TARGET}")
      endif()
    endif()

    # Compose arguments for configuration
    set(GEN_ARGS)
    set(CONF_ARGS)

    if(CMAKE_GENERATOR_PLATFORM)
      set(GEN_ARGS ${GEN_ARGS} "-A${CMAKE_GENERATOR_PLATFORM}")
    endif()
    if(CMAKE_TOOLCHAIN_FILE)
      set(GEN_ARGS ${GEN_ARGS} -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE})
    endif()

    if(args_CMAKE_ARGS)
      set(CONF_ARGS "${args_CMAKE_ARGS}")
    endif()

    # Force ignore build warnings from externals
    if(MSVC)
      set(ENV_SETTINGS "CXXFLAGS=\"-W0\"")
    else()
      set(ENV_SETTINGS "CXXFLAGS=\"-w\"")
    endif()

    # Configure project
    execute_process(
      COMMAND ${CMAKE_COMMAND} -E env "${ENV_SETTINGS}" ${CMAKE_COMMAND} "--no-warn-unused-cli" "-G${CMAKE_GENERATOR}" ${GEN_ARGS} ${CONF_ARGS}
        -DCMAKE_INSTALL_PREFIX:PATH=${INSTALL_DIR}
        -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
        -DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}
        -DCMAKE_BUILD_TYPE=${CONFIG}
        ${SOURCE_DIR}
      WORKING_DIRECTORY "${BINARY_DIR}"
      RESULT_VARIABLE CONFIG_RESULT
      OUTPUT_QUIET)

    if(NOT "${CONFIG_RESULT}" STREQUAL "0")
      message(FATAL_ERROR "Fatal error while configuring ${TARGET}")
    endif()

    # Remove files so that the build process is run again
    execute_process(
      COMMAND ${CMAKE_COMMAND} -E remove -f EXTERNAL_BUILT
        EXTERNAL_BUILT_Release EXTERNAL_BUILT_RelWithDebInfo EXTERNAL_BUILT_Debug
      WORKING_DIRECTORY "${BINARY_DIR}"
      OUTPUT_QUIET)

    external_set_typed_property(${TARGET} NEW_VERSION FALSE BOOL)
  endif()

  # Get and check byproducts
  if(NOT args_BUILD_BYPRODUCTS)
    message(FATAL_ERROR "No byproducts declared")
  endif()

  # Add command for building
  if(args_SHARED)
    external_set_typed_property(${TARGET} SHARED TRUE BOOL)

    set(BYPRODUCTS)
    set(INSTALL_COMMANDS)
    foreach(BYPRODUCT IN LISTS args_BUILD_BYPRODUCTS)
      string(REPLACE "<INSTALL_DIR>" "${INSTALL_DIR}" SOURCE_BYPRODUCT ${BYPRODUCT})
      string(REPLACE "<INSTALL_DIR>" "${INSTALL_DIR}/../../_deps_install" TARGET_BYPRODUCT ${BYPRODUCT})

      list(APPEND BYPRODUCTS ${SOURCE_BYPRODUCT})
      list(APPEND INSTALL_COMMANDS COMMAND ${CMAKE_COMMAND} -E copy \"${SOURCE_BYPRODUCT}\" \"${TARGET_BYPRODUCT}\")
    endforeach()

    string(REPLACE "<INSTALL_DIR>" "${INSTALL_DIR}/../../_deps_install" COMMANDS "${COMMANDS}")

    # Determine number of CPU cores
    include(ProcessorCount)
    ProcessorCount(NUM_CPU_CORES)
    if(NUM_CPU_CORES EQUAL 0)
      set(NUM_CPU_CORES 1)
    endif()

    add_custom_command(OUTPUT "${BINARY_DIR}/EXTERNAL_BUILT"
      COMMAND ${CMAKE_COMMAND} --build . --parallel ${NUM_CPU_CORES} --config Release
      COMMAND ${CMAKE_COMMAND} --build . --target install --config Release
      COMMAND ${CMAKE_COMMAND} -E make_directory \"${INSTALL_DIR}/../../_deps_install\"
      ${INSTALL_COMMANDS}
      ${COMMANDS}
      COMMAND ${CMAKE_COMMAND} -E touch EXTERNAL_BUILT
      WORKING_DIRECTORY "${BINARY_DIR}"
      BYPRODUCTS ${BYPRODUCTS})

    add_custom_target(${TARGET}_ext DEPENDS "${BINARY_DIR}/EXTERNAL_BUILT")
  elseif(MULTICONFIG)
    external_set_typed_property(${TARGET} SHARED FALSE BOOL)

    set(INSTALL_COMMANDS)
    foreach(BYPRODUCT IN LISTS args_BUILD_BYPRODUCTS)
      string(REPLACE "<INSTALL_DIR>" "${INSTALL_DIR}" SOURCE_BYPRODUCT ${BYPRODUCT})
      string(REPLACE "<INSTALL_DIR>" "${INSTALL_DIR}/$<CONFIG>" TARGET_BYPRODUCT ${BYPRODUCT})
      string(REPLACE "<SUFFIX>" "$<$<CONFIG:Debug>:${args_DEBUG_SUFFIX}>" SOURCE_BYPRODUCT ${SOURCE_BYPRODUCT})
      string(REPLACE "<SUFFIX>" "$<$<CONFIG:Debug>:${args_DEBUG_SUFFIX}>" TARGET_BYPRODUCT ${TARGET_BYPRODUCT})

      list(APPEND INSTALL_COMMANDS COMMAND ${CMAKE_COMMAND} -E copy "${SOURCE_BYPRODUCT}" "${TARGET_BYPRODUCT}")
    endforeach()

    add_custom_target(${TARGET}_ext
      COMMAND ${CMAKE_COMMAND}
        -DCONFIG=$<CONFIG>
        -DINSTALL_DIR="${INSTALL_DIR}/$<CONFIG>"
        "-DINSTALL_COMMANDS=\"${INSTALL_COMMANDS}\""
        "-DCOMMANDS=\"${COMMANDS}\""
        -P "${EXTERNAL_SCRIPTS_DIR}/External_build.cmake"
      DEPENDS "${EXTERNAL_SCRIPTS_DIR}/External_build.cmake"
      WORKING_DIRECTORY "${BINARY_DIR}")
  else()
    external_set_typed_property(${TARGET} SHARED FALSE BOOL)

    set(BYPRODUCTS)
    set(INSTALL_COMMANDS)
    foreach(BYPRODUCT IN LISTS args_BUILD_BYPRODUCTS)
      string(REPLACE "<INSTALL_DIR>" "${INSTALL_DIR}" SOURCE_BYPRODUCT ${BYPRODUCT})
      string(REPLACE "<INSTALL_DIR>" "${INSTALL_DIR}/${CONFIG}" TARGET_BYPRODUCT ${BYPRODUCT})

      if(CONFIG STREQUAL Debug)
        string(REPLACE "<SUFFIX>" "${args_DEBUG_SUFFIX}" SOURCE_BYPRODUCT ${SOURCE_BYPRODUCT})
        string(REPLACE "<SUFFIX>" "${args_DEBUG_SUFFIX}" TARGET_BYPRODUCT ${TARGET_BYPRODUCT})
      else()
        string(REPLACE "<SUFFIX>" "" SOURCE_BYPRODUCT ${SOURCE_BYPRODUCT})
        string(REPLACE "<SUFFIX>" "" TARGET_BYPRODUCT ${TARGET_BYPRODUCT})
      endif()

      list(APPEND BYPRODUCTS ${TARGET_BYPRODUCT})
      list(APPEND INSTALL_COMMANDS COMMAND ${CMAKE_COMMAND} -E copy "${SOURCE_BYPRODUCT}" "${TARGET_BYPRODUCT}")
    endforeach()

    add_custom_target(${TARGET}_ext
      COMMAND ${CMAKE_COMMAND}
        -DCONFIG=${CONFIG}
        -DINSTALL_DIR="${INSTALL_DIR}/${CONFIG}"
        "-DINSTALL_COMMANDS=\"${INSTALL_COMMANDS}\""
        "-DCOMMANDS=\"${COMMANDS}\""
        -P "${EXTERNAL_SCRIPTS_DIR}/External_build.cmake"
      DEPENDS "${EXTERNAL_SCRIPTS_DIR}/External_build.cmake"
      WORKING_DIRECTORY "${BINARY_DIR}"
      BYPRODUCTS ${BYPRODUCTS})
  endif()

  # Set external target properties
  set_target_properties(${TARGET}_ext PROPERTIES FOLDER ${FOLDER_NAME})

  if(args_DEPENDS)
    foreach(DEP IN LISTS args_DEPENDS)
      if(TARGET ${DEP})
        add_dependencies(${TARGET}_ext ${DEP})
      elseif(TARGET ${DEP}_ext)
        add_dependencies(${TARGET}_ext ${DEP}_ext)
      endif()
    endforeach()
  endif()

  # Create ALL target for building all external libraries at once
  if(NOT TARGET _ALL_EXTERNALS)
    add_custom_target(_ALL_EXTERNALS)
    set_target_properties(_ALL_EXTERNALS PROPERTIES FOLDER ${FOLDER_NAME})
  endif()

  add_dependencies(_ALL_EXTERNALS ${TARGET}_ext)

  # Create install target for installing all shared external libraries
  if (args_SHARED)
    if(NOT TARGET _INSTALL_EXTERNALS)
      add_custom_target(_INSTALL_EXTERNALS
        DEPENDS _ALL_EXTERNALS
        COMMAND ${CMAKE_COMMAND} -E copy_directory \"${INSTALL_DIR}/../../_deps_install\" \"${CMAKE_INSTALL_PREFIX}/\")

      set_target_properties(_INSTALL_EXTERNALS PROPERTIES FOLDER ${FOLDER_NAME})
    endif()

    if(WIN32)
      install(DIRECTORY "${INSTALL_DIR}/../../_deps_install/bin" DESTINATION "${CMAKE_INSTALL_PREFIX}")
    else()
      install(DIRECTORY "${INSTALL_DIR}/../../_deps_install/${CMAKE_INSTALL_LIBDIR}" DESTINATION "${CMAKE_INSTALL_PREFIX}")
      if (NOT ${CMAKE_INSTALL_LIBDIR} STREQUAL "lib")
        install(DIRECTORY "${INSTALL_DIR}/../../_deps_install/lib" DESTINATION "${CMAKE_INSTALL_PREFIX}")
      endif()
    endif()
  endif()
endfunction(add_external_project)





#
# Adds an external library, depending on an external project.
#
# add_external_library(<target>
#     PROJECT <external_project>
#     LIBRARY "<library_name>.dll|so"
#     IMPORT_LIBRARY "<library_name>.lib"
#     INTERFACE_LIBRARIES "<external_library>*"
#     DEBUG_SUFFIX <suffix>)
#
function(add_external_library TARGET)
  set(ARGS_ONE_VALUE PROJECT LIBRARY IMPORT_LIBRARY DEBUG_SUFFIX)
  set(ARGS_MULT_VALUES INTERFACE_LIBRARIES)
  cmake_parse_arguments(args "" "${ARGS_ONE_VALUE}" "${ARGS_MULT_VALUES}" ${ARGN})

  # Get default arguments
  _argument_default(PROJECT ${TARGET})
  _argument_default(LIBRARY "NOTFOUND")
  _argument_default(IMPORT_LIBRARY "NOTFOUND")
  _argument_default(INTERFACE_LIBRARIES "")
  _argument_default(DEBUG_SUFFIX "")

  # Guess library properties, unless set.
  external_get_property(${PROJECT} SHARED)
  external_get_property(${PROJECT} INSTALL_DIR)
  external_get_property(${PROJECT} CONFIG_DIR)

  # Create include directory as required by INTERFACE_INCLUDE_DIRECTORIES.
  file(MAKE_DIRECTORY "${INSTALL_DIR}/include")

  # Add an imported library.
  if(SHARED)
    add_library(${TARGET} SHARED IMPORTED GLOBAL)
    add_dependencies(${TARGET} ${PROJECT}_ext)
    set_target_properties(${TARGET} PROPERTIES
      INTERFACE_INCLUDE_DIRECTORIES "${INSTALL_DIR}/include;${CONFIG_DIR}"
      INTERFACE_LINK_LIBRARIES "${INTERFACE_LIBRARIES}"
      IMPORTED_CONFIGURATIONS "Release"
      IMPORTED_LOCATION "${INSTALL_DIR}/${LIBRARY}"
      IMPORTED_IMPLIB "${INSTALL_DIR}/${IMPORT_LIBRARY}")
  else()
    string(REPLACE "<SUFFIX>" "" LIBRARY_RELEASE ${LIBRARY})
    string(REPLACE "<SUFFIX>" "" LIBRARY_RELWITHDEBINFO ${LIBRARY})
    string(REPLACE "<SUFFIX>" "${DEBUG_SUFFIX}" LIBRARY_DEBUG ${LIBRARY})

    add_library(${TARGET} STATIC IMPORTED GLOBAL)
    add_dependencies(${TARGET} ${PROJECT}_ext)
    set_target_properties(${TARGET} PROPERTIES
      INTERFACE_INCLUDE_DIRECTORIES "${INSTALL_DIR}/include;${CONFIG_DIR}"
      INTERFACE_LINK_LIBRARIES "${INTERFACE_LIBRARIES}"
      IMPORTED_CONFIGURATIONS "${CMAKE_CONFIGURATION_TYPES}"
      IMPORTED_LOCATION "${INSTALL_DIR}/Release/${LIBRARY_RELEASE}"
      IMPORTED_LOCATION_RELWITHDEBINFO "${INSTALL_DIR}/RelWithDebInfo/${LIBRARY_RELWITHDEBINFO}"
      IMPORTED_LOCATION_DEBUG "${INSTALL_DIR}/Debug/${LIBRARY_DEBUG}")
  endif()
endfunction(add_external_library)
