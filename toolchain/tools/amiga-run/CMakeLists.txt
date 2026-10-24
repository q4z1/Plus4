# amiga-run: a script-driven front end for the vAmiga core (see amiga-run.cpp).
# Built by toolchain/tools/build-tools.sh; VAMIGA_CORE points to vAmiga's Core folder.
cmake_minimum_required(VERSION 3.16)
project(amiga_run CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED True)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()
add_subdirectory(${VAMIGA_CORE} vamiga)
add_executable(amiga-run amiga-run.cpp)
target_link_libraries(amiga-run PRIVATE VACore)
