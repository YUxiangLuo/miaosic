# Keep the patched engine local to this project. Flutter still produces Dart
# snapshots and plugin headers using the matching, unmodified installed SDK.
if("$ENV{MIAOSIC_USE_SYSTEM_FLUTTER_ENGINE}" STREQUAL "1")
  message(WARNING "Using the stock Flutter engine; Wayland frame sync is disabled")
  return()
endif()

set(MIAOSIC_ROOT "${CMAKE_CURRENT_LIST_DIR}/..")
file(READ "${MIAOSIC_ROOT}/patches/flutter/engine.json" MIAOSIC_ENGINE_PIN)
string(JSON MIAOSIC_ENGINE_REVISION GET "${MIAOSIC_ENGINE_PIN}" engine_revision)
string(JSON MIAOSIC_ENGINE_RECIPE GET "${MIAOSIC_ENGINE_PIN}" build_recipe)
file(SHA256 "${MIAOSIC_ROOT}/patches/flutter/linux-wayland-frame-sync.patch" MIAOSIC_PATCH_HASH)
string(TOLOWER "${CMAKE_BUILD_TYPE}" MIAOSIC_ENGINE_MODE)
set(MIAOSIC_ENGINE_DIR "${MIAOSIC_ROOT}/.dart_tool/miaosic_engine/${MIAOSIC_ENGINE_MODE}")
set(MIAOSIC_ENGINE_FINGERPRINT "${MIAOSIC_ENGINE_REVISION}:${MIAOSIC_PATCH_HASH}:${MIAOSIC_ENGINE_MODE}:${MIAOSIC_ENGINE_RECIPE}")
set(MIAOSIC_PREPARE "python3 scripts/build_linux_engine.py --mode ${MIAOSIC_ENGINE_MODE}")

# generated_config.cmake is scoped to the Flutter subdirectory.
get_directory_property(MIAOSIC_FLUTTER_ROOT DIRECTORY "${FLUTTER_MANAGED_DIR}"
  DEFINITION FLUTTER_ROOT)
file(READ "${MIAOSIC_FLUTTER_ROOT}/bin/cache/engine.stamp" MIAOSIC_SDK_ENGINE)
string(STRIP "${MIAOSIC_SDK_ENGINE}" MIAOSIC_SDK_ENGINE)
if(NOT MIAOSIC_SDK_ENGINE STREQUAL MIAOSIC_ENGINE_REVISION)
  message(FATAL_ERROR "Flutter engine does not match patches/flutter/engine.json. Use the pinned Flutter SDK.")
endif()
foreach(MIAOSIC_FILE fingerprint sha256 libflutter_linux_gtk.so)
  if(NOT EXISTS "${MIAOSIC_ENGINE_DIR}/${MIAOSIC_FILE}")
    message(FATAL_ERROR "Prepare the Wayland engine first: ${MIAOSIC_PREPARE}")
  endif()
endforeach()
file(READ "${MIAOSIC_ENGINE_DIR}/fingerprint" MIAOSIC_INSTALLED_FINGERPRINT)
string(STRIP "${MIAOSIC_INSTALLED_FINGERPRINT}" MIAOSIC_INSTALLED_FINGERPRINT)
if(NOT MIAOSIC_INSTALLED_FINGERPRINT STREQUAL MIAOSIC_ENGINE_FINGERPRINT)
  message(FATAL_ERROR "Patched engine is stale. Run: ${MIAOSIC_PREPARE}")
endif()
file(READ "${MIAOSIC_ENGINE_DIR}/sha256" MIAOSIC_EXPECTED_HASH)
string(STRIP "${MIAOSIC_EXPECTED_HASH}" MIAOSIC_EXPECTED_HASH)
set(FLUTTER_LIBRARY "${MIAOSIC_ENGINE_DIR}/libflutter_linux_gtk.so")
file(SHA256 "${FLUTTER_LIBRARY}" MIAOSIC_ACTUAL_HASH)
if(NOT MIAOSIC_EXPECTED_HASH STREQUAL MIAOSIC_ACTUAL_HASH)
  message(FATAL_ERROR "Patched engine checksum failed. Run: ${MIAOSIC_PREPARE}")
endif()
set_property(TARGET flutter PROPERTY INTERFACE_LINK_LIBRARIES
  "${FLUTTER_LIBRARY};PkgConfig::GTK;PkgConfig::GLIB;PkgConfig::GIO")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
  "${MIAOSIC_ROOT}/patches/flutter/engine.json"
  "${MIAOSIC_ROOT}/patches/flutter/linux-wayland-frame-sync.patch"
  "${MIAOSIC_ENGINE_DIR}/fingerprint")
message(STATUS "Using Miaosic Wayland engine (${MIAOSIC_ENGINE_MODE})")
