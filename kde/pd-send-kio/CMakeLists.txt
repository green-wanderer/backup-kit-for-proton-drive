# Build:   cmake -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build
# Install: sudo cmake --install build && kbuildsycoca6
cmake_minimum_required(VERSION 3.16)
project(pd-send-kio VERSION 1.0 LANGUAGES CXX)

find_package(ECM 6.0.0 REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
    set(CMAKE_INSTALL_PREFIX /usr CACHE PATH "" FORCE)
endif()

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Widgets)
find_package(KF6 REQUIRED COMPONENTS CoreAddons KIO)

set(CMAKE_AUTOMOC ON)

kcoreaddons_add_plugin(pd-send-kio INSTALL_NAMESPACE "kf6/kfileitemaction" SOURCES pd-send-kio.cpp)
target_link_libraries(pd-send-kio Qt6::Widgets KF6::KIOWidgets)
