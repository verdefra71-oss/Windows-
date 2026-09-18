cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

set(BINARY_NAME "Gestione Preventivi")
set(APPLICATION_ID "com.preventivi.gestione")

cmake_policy(SET CMP0063 NEW)

set(CMAKE_INSTALL_PREFIX "${CMAKE_BINARY_DIR}/bundle" CACHE PATH "Installation Directory" FORCE)

set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

include(flutter/ephemeral/generated_config.cmake)
include(flutter/ephemeral/generated_plugins.cmake)

add_subdirectory("runner")

set(BUILD_BUNDLE_DIR "${PROJECT_BINARY_DIR}/bundle")

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${BUILD_BUNDLE_DIR}/data")
install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${BUILD_BUNDLE_DIR}")

install(DIRECTORY "${PROJECT_BINARY_DIR}/flutter_assets" DESTINATION "${BUILD_BUNDLE_DIR}")

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}" DESTINATION "${BUILD_BUNDLE_DIR}")
endif()

install(FILES "${AOT_LIBRARY}" DESTINATION "${BUILD_BUNDLE_DIR}/data" CONFIGURATIONS Release)
install(FILES "${FLUTTER_ENGINE_LIBRARY}" DESTINATION "${BUILD_BUNDLE_DIR}")
