# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(pos_app LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "pos_app")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)

# webview_windows 0.4.0 otherwise consumes the C++/WinRT headers bundled with
# older Windows SDKs. Those headers do not compile cleanly in C++20 mode on
# current Visual Studio toolchains. Pin Microsoft's maintained projection and
# import its MSBuild targets into the plugin so release builds remain portable.
if(TARGET webview_windows_plugin)
  # 2.0.210503.1 is a projection line compatible with the Visual Studio 2019
  # toolchain still supported by this desktop application's CI.
  set(PIKI_CPPWINRT_VERSION "2.0.210503.1")
  find_program(PIKI_NUGET nuget)
  if(NOT PIKI_NUGET)
    set(PIKI_NUGET "${CMAKE_BINARY_DIR}/piki_nuget.exe")
    if(NOT EXISTS "${PIKI_NUGET}")
      file(DOWNLOAD
        "https://dist.nuget.org/win-x86-commandline/v5.10.0/nuget.exe"
        "${PIKI_NUGET}"
        EXPECTED_HASH SHA256=852b71cc8c8c2d40d09ea49d321ff56fd2397b9d6ea9f96e532530307bbbafd3
      )
    endif()
  endif()

  add_custom_target(piki_cppwinrt_dependencies ALL)
  add_custom_command(
    TARGET piki_cppwinrt_dependencies PRE_BUILD
    COMMAND "${PIKI_NUGET}" install Microsoft.Windows.CppWinRT
      -Version "${PIKI_CPPWINRT_VERSION}"
      -ExcludeVersion
      -OutputDirectory "${CMAKE_BINARY_DIR}/packages"
    DEPENDS "${PIKI_NUGET}"
  )
  add_dependencies(webview_windows_plugin piki_cppwinrt_dependencies)
  get_target_property(PIKI_WEBVIEW_COMPILE_OPTIONS
    webview_windows_plugin COMPILE_OPTIONS)
  if(PIKI_WEBVIEW_COMPILE_OPTIONS)
    list(FILTER PIKI_WEBVIEW_COMPILE_OPTIONS EXCLUDE REGEX "^/await$")
    set_property(TARGET webview_windows_plugin PROPERTY
      COMPILE_OPTIONS "${PIKI_WEBVIEW_COMPILE_OPTIONS}")
  endif()
  get_target_property(PIKI_WEBVIEW_COMPILE_DEFINITIONS
    webview_windows_plugin COMPILE_DEFINITIONS)
  if(PIKI_WEBVIEW_COMPILE_DEFINITIONS)
    list(FILTER PIKI_WEBVIEW_COMPILE_DEFINITIONS
      EXCLUDE REGEX "^_HAS_EXCEPTIONS=0$")
    set_property(TARGET webview_windows_plugin PROPERTY
      COMPILE_DEFINITIONS "${PIKI_WEBVIEW_COMPILE_DEFINITIONS}")
  endif()
  set_target_properties(webview_windows_plugin PROPERTIES
    VS_GLOBAL_CppWinRTPackage "true"
    VS_GLOBAL_CppWinRTPackageDir "${CMAKE_BINARY_DIR}/packages/Microsoft.Windows.CppWinRT/"
  )
  target_link_libraries(webview_windows_plugin PRIVATE
    "${CMAKE_BINARY_DIR}/packages/Microsoft.Windows.CppWinRT/build/native/Microsoft.Windows.CppWinRT.targets"
  )
endif()


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
