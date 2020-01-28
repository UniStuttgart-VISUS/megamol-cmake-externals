# External dependencies

The system for including external dependencies in MegaMol is a process split into two phases, corresponding to CMake configuration and the build process.

In the CMake configuration run, in which the external is first requested, it is downloaded from a git repository by providing a URL and tag (or commit hash), and configured in a separate process and folder. This is done to prevent global CMake options from clashing. In later CMake configuration runs, this configuration of the external dependencies is not re-run, except when manually requested by setting the appropriate CMake cache variable ```EXTERNAL_<NAME>_NEW_VERSION``` to ```TRUE```, or when the URL, tag or build type change.

When building MegaMol, all external dependencies are only built if they have not been built before. Afterwards, only by setting ```EXTERNAL_<NAME>_NEW_VERSION``` to ```TRUE``` can the build process be triggered again. This ensures that they are not rebuilt unnecessarily, but built when their version change.

<!-- TOC -->

## Contents

- [Using external dependencies](#using-external-dependencies)
- [Adding new external dependencies](#adding-new-external-dependencies)
  - [Header-only libraries](#header-only-libraries)
  - [Built libraries](#built-libraries)

<!-- /TOC -->

## Using external dependencies

External dependencies are split into two categories: header-only libraries and libraries that have to be built into a static (```.a```/```.lib```) or dynamic (```.so```/```.dll```) library. Both kinds are defined in the ```CMakeExternals.cmake``` file in the MegaMol main directory and can be requested in the plugins using the command ```require_external(<NAME>)```. Generally, this command makes available the target ```<NAME>```, which provides all necessary information on where to find the library and include files.

## Adding new external dependencies

The setup for header-only and built libraries need different parameters and commands.

### Header-only libraries

For setting up a header-only library, the following command is used:

```
add_external_headeronly_project(<NAME>
   GIT_REPOSITORY <GIT_REPOSITORY>
  [GIT_TAG <GIT_TAG>]
  [INCLUDE_DIR <INCLUDE_DIR>]
  [DEPENDS <DEPENDS>...])
```

| Parameter              | Description  |
| ---------------------- | ------------ |
| ```<NAME>```           | Target name, usually the official name of the library or its abbreviation. |
| ```<GIT_REPOSITORY>``` | URL of the git repository. |
| ```<GIT_TAG>```        | Tag or commit hash for getting a specific version, ensuring compatibility. Default behavior is to get the latest version. |
| ```<INCLUDE_DIR>```    | Relative directory where the include files can be found, usually ```include```. Defaults to the main source directory. |
| ```<DEPENDS>```        | Targets this library depends on, if any. |

In the following example, the library Delaunator is downloaded from ```https://github.com/delfrrr/delaunator-cpp.git``` in its version ```v0.4.0```. The header files can be found in the folder ```include```.

```
add_external_headeronly_project(Delaunator
  GIT_REPOSITORY https://github.com/delfrrr/delaunator-cpp.git
  GIT_TAG "v0.4.0"
  INCLUDE_DIR "include")
```

For more examples on how to include header-only libraries, see the ```CMakeExternals.cmake``` file in the MegaMol main directory.

Additionally, information about the header-only libraries can be queried with the command ```external_get_property(<NAME> <VARIABLE>)```, where variable has to be one of the provided variables in the following table, and at the same time is used as local variable name for storing the queried results.

| Variable       | Description |
| -------------- | ----------- |
| GIT_REPOSITORY | The URL of the git repository. |
| GIT_TAG        | The git tag or commit hash of the downloaded library. |
| SOURCE_DIR     | Source directory, where the downloaded files reside. |

### Built libraries

Libraries that are built into static or dynamic libraries, follow a process executing two different commands. The first command is responsible for setting up the project, while the second command creates the interface targets.

Similarly to the header-only libraries, the setup uses a command specifying the source and type of the library, additionally providing information for the configuration and build processes:

```
add_external_project(<NAME> SHARED|STATIC
   GIT_REPOSITORY <GIT_REPOSITORY>
  [GIT_TAG <GIT_TAG>]
  [PATCH_COMMAND <PATCH_COMMAND>...]
  [CMAKE_ARGS <CMAKE_ARGUMENTS>...]
  BUILD_BYPRODUCTS <OUTPUT_LIBRARIES>...
  [COMMANDS <INSTALL_COMMANDS>...]
  [DEBUG_SUFFIX <DEBUG_SUFFIX>]
  [DEPENDS <DEPENDS>...])
```

| Parameter                     | Description |
| ----------------------------- | ----------- |
| ```<NAME>```                  | Project name, usually the official name of the library or its abbreviation. |
| ```SHARED \| STATIC```        | Indicate to build a shared (```.so```/```.dll```) or static (```.a```/```.lib```) library. Shared libraries are always built as Release, static libraries according to user selection. |
| ```<GIT_REPOSITORY>```        | URL of the git repository. |
| ```<GIT_TAG>```               | Tag or commit hash for getting a specific version, ensuring compatibility. Default behavior is to get the latest version. |
| ```<PATCH_COMMAND>```         | Command that is run before the configuration step and is mostly used to apply patches or providing a modified ```CMakeLists.txt``` file. |
| ```<CMAKE_ARGS>```            | Arguments that are passed to CMake for the configuration of the external library. |
| ```<BUILD_BYPRODUCTS>```      | Specifies the output libraries, which are automatically installed if it is a dynamic library. This must include the import library on Windows systems. |
| ```<COMMANDS>```              | Commands that are executed after the build process finished, allowing for custom install commands. |
| ```<DEBUG_SUFFIX>```          | Specify a suffix for the debug version of the library. The position of this suffix has to be specified by providing ```<SUFFIX>``` in the library name. |
| ```<DEPENDS>```               | Targets this library depends on, if any. |

The second command creates the actual interface targets. Note that for some libraries, multiple targets have to be created.

```
add_external_library(<NAME> [PROJECT <PROJECT>]
   LIBRARY <LIBRARY>
  [IMPORT_LIBRARY <IMPORT_LIBRARY>]
  [INTERFACE_LIBRARIES <INTERFACE_LIBRARIES>...]
  [DEBUG_SUFFIX <DEBUG_SUFFIX>])
```

| Parameter                     | Description |
| ----------------------------- | ----------- |
| ```<NAME>```                  | Target name, for the main target this is usually the official name of the library or its abbreviation. |
| ```<PROJECT>```               | If the target name does not match the name provided in the ```add_external_project``` command, the project has to be set accordingly. |
| ```<LIBRARY>```               | The created library file, in case of a shared library a ```.so``` or ```.dll``` file, or ```.a``` or ```.lib``` for a static library. |
| ```<IMPORT_LIBRARY>```        | If the library is a shared library, this defines the import library (```.lib```) on Windows systems. This has to be set for shared libraries. |
| ```<INTERFACE_LIBRARIES>```   | Additional libraries the external library depends on. |
| ```<DEBUG_SUFFIX>```          | Specify a suffix for the debug version of the library. The position of this suffix has to be specified by providing ```<SUFFIX>``` in the library name and has to match the debug suffix provided to the ```add_external_project``` command. |

An example for a dynamic library is as follows, where the ```tracking``` library ```v2.0``` is defined as a dynamic library and downloaded from the VISUS github repository at ```https://github.com/UniStuttgart-VISUS/mm-tracking```. It builds two libraries, ```tracking``` and ```NatNetLib```, and uses the CMake flag ```-DCREATE_TRACKING_TEST_PROGRAM=OFF``` to prevent the building of a test program. Both libraries are created providing the paths to the respective dynamic and import libraries. Note that only the ```NatNetLib``` has to specify the project as its name does not match the external library.

```
add_external_project(tracking SHARED
  GIT_REPOSITORY https://github.com/UniStuttgart-VISUS/mm-tracking
  GIT_TAG "v2.0"
  BUILD_BYPRODUCTS
    "<INSTALL_DIR>/bin/tracking.dll"
    "<INSTALL_DIR>/lib/tracking.lib"
    "<INSTALL_DIR>/bin/NatNetLib.dll"
    "<INSTALL_DIR>/lib/NatNetLib.lib"
  CMAKE_ARGS
    -DCREATE_TRACKING_TEST_PROGRAM=OFF)
```

```
add_external_library(tracking
  LIBRARY "bin/tracking.dll"
  IMPORT_LIBRARY "lib/tracking.lib")
```

```
add_external_library(natnet
  PROJECT tracking
  LIBRARY "bin/NatNetLib.dll"
  IMPORT_LIBRARY "lib/NatNetLib.lib")
```

Further examples on how to include dynamic and static libraries can be found in the ```CMakeExternals.cmake``` file in the MegaMol main directory.

Additionally, information about the libraries can be queried with the command ```external_get_property(<NAME> <VARIABLE>)```, where variable has to be one of the provided variables in the following table, and at the same time is used as local variable name for storing the queried results.

| Variable       | Description |
| -------------- | ----------- |
| GIT_REPOSITORY | The URL of the git repository. |
| GIT_TAG        | The git tag or commit hash of the downloaded library. |
| SOURCE_DIR     | Source directory, where the downloaded files reside. |
| BINARY_DIR     | Directory of the CMake configuration files. |
| INSTALL_DIR    | Target directory for the local installation. Note that for multi-configuration systems, the built static libraries are in a subdirectory corresponding to their build type. |
| SHARED         | Indicates that the library was built as a dynamic library if ```TRUE```, or a static library otherwise. |
| BUILD_TYPE     | Build type of the output library on single-configuration systems. |
