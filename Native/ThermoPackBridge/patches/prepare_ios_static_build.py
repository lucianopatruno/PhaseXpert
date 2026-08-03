#!/usr/bin/env python3
"""Prepare clean ThermoPack v2.2.4 sources for an iOS-only static build.

This patch changes build mechanics only. It does not alter equations, component
records, interaction parameters, solver algorithms, or calculated values.
"""
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: prepare_ios_static_build.py /path/to/thermopack")

root = Path(sys.argv[1])
top = root / "CMakeLists.txt"
src = root / "src" / "CMakeLists.txt"
top_text = top.read_text()
src_text = src.read_text()

old_block = '''    execute_process(COMMAND bash -c "arch" OUTPUT_VARIABLE PROC)
    set(tp_flags_common "-cpp -fPIC -fdefault-real-8 -fdefault-double-8 -frecursive -fopenmp -Wno-unused-function -Wno-unused-variable")

    include(CheckCompilerFlag)
    check_compiler_flag(Fortran "-arch arm64" arm64_supported)
    if(arm64_supported)
        set(gf_proc "-arch arm64")
        set(gf_march "-arch arm64 -fno-expensive-optimizations")
    else()
        set(gf_proc "-mieee-fp")
        set(gf_march "-march=x86-64 -msse2")
    endif()
'''
new_block = '''    set(tp_flags_common "-cpp -fPIC -fdefault-real-8 -fdefault-double-8")
    set(gf_proc "")
    set(gf_march "")
'''
if old_block not in top_text:
    raise SystemExit("ThermoPack root CMake layout changed; refusing an unreviewed patch")
top_text = top_text.replace(old_block, new_block)
top_text = top_text.replace(
    '''    if(APPLE)
        set(CMAKE_FORTRAN_COMPILER /opt/homebrew/bin/gfortran)
        set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING "The OSX architecture")
    endif()
''',
    '''    # PhaseXpert supplies the reviewed cross compiler and target architecture.
'''
)

if "find_package(LAPACK REQUIRED)" not in src_text:
    raise SystemExit("ThermoPack LAPACK configuration changed")
src_text = src_text.replace(
    "find_package(LAPACK REQUIRED)",
    'set(LAPACK_LIBRARIES "-framework Accelerate")'
)
src_text = src_text.replace(
    "add_library(thermopack SHARED $<TARGET_OBJECTS:thermopack_obj>)",
    "add_library(thermopack SHARED EXCLUDE_FROM_ALL $<TARGET_OBJECTS:thermopack_obj>)"
)
src_text = src_text.replace(
    "add_executable(run_thermopack ${CMAKE_CURRENT_SOURCE_DIR}/thermopack.f90)",
    "add_executable(run_thermopack EXCLUDE_FROM_ALL ${CMAKE_CURRENT_SOURCE_DIR}/thermopack.f90)"
)

top.write_text(top_text)
src.write_text(src_text)