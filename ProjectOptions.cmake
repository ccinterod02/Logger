include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(Logger_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(Logger_setup_options)
  option(Logger_ENABLE_HARDENING "Enable hardening" ON)
  option(Logger_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    Logger_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    Logger_ENABLE_HARDENING
    OFF)

  Logger_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR Logger_PACKAGING_MAINTAINER_MODE)
    option(Logger_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(Logger_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(Logger_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(Logger_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(Logger_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(Logger_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(Logger_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(Logger_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(Logger_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(Logger_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(Logger_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(Logger_ENABLE_PCH "Enable precompiled headers" OFF)
    option(Logger_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(Logger_ENABLE_IPO "Enable IPO/LTO" ON)
    option(Logger_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(Logger_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(Logger_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(Logger_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(Logger_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(Logger_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(Logger_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(Logger_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(Logger_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(Logger_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(Logger_ENABLE_PCH "Enable precompiled headers" OFF)
    option(Logger_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      Logger_ENABLE_IPO
      Logger_WARNINGS_AS_ERRORS
      Logger_ENABLE_USER_LINKER
      Logger_ENABLE_SANITIZER_ADDRESS
      Logger_ENABLE_SANITIZER_LEAK
      Logger_ENABLE_SANITIZER_UNDEFINED
      Logger_ENABLE_SANITIZER_THREAD
      Logger_ENABLE_SANITIZER_MEMORY
      Logger_ENABLE_UNITY_BUILD
      Logger_ENABLE_CLANG_TIDY
      Logger_ENABLE_CPPCHECK
      Logger_ENABLE_COVERAGE
      Logger_ENABLE_PCH
      Logger_ENABLE_CACHE)
  endif()

  Logger_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (Logger_ENABLE_SANITIZER_ADDRESS OR Logger_ENABLE_SANITIZER_THREAD OR Logger_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(Logger_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(Logger_global_options)
  if(Logger_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    Logger_enable_ipo()
  endif()

  Logger_supports_sanitizers()

  if(Logger_ENABLE_HARDENING AND Logger_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR Logger_ENABLE_SANITIZER_UNDEFINED
       OR Logger_ENABLE_SANITIZER_ADDRESS
       OR Logger_ENABLE_SANITIZER_THREAD
       OR Logger_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${Logger_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${Logger_ENABLE_SANITIZER_UNDEFINED}")
    Logger_enable_hardening(Logger_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(Logger_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(Logger_warnings INTERFACE)
  add_library(Logger_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  Logger_set_project_warnings(
    Logger_warnings
    ${Logger_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(Logger_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    Logger_configure_linker(Logger_options)
  endif()

  include(cmake/Sanitizers.cmake)
  Logger_enable_sanitizers(
    Logger_options
    ${Logger_ENABLE_SANITIZER_ADDRESS}
    ${Logger_ENABLE_SANITIZER_LEAK}
    ${Logger_ENABLE_SANITIZER_UNDEFINED}
    ${Logger_ENABLE_SANITIZER_THREAD}
    ${Logger_ENABLE_SANITIZER_MEMORY})

  set_target_properties(Logger_options PROPERTIES UNITY_BUILD ${Logger_ENABLE_UNITY_BUILD})

  if(Logger_ENABLE_PCH)
    target_precompile_headers(
      Logger_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(Logger_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    Logger_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(Logger_ENABLE_CLANG_TIDY)
    Logger_enable_clang_tidy(Logger_options ${Logger_WARNINGS_AS_ERRORS})
  endif()

  if(Logger_ENABLE_CPPCHECK)
    Logger_enable_cppcheck(${Logger_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(Logger_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    Logger_enable_coverage(Logger_options)
  endif()

  if(Logger_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(Logger_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(Logger_ENABLE_HARDENING AND NOT Logger_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR Logger_ENABLE_SANITIZER_UNDEFINED
       OR Logger_ENABLE_SANITIZER_ADDRESS
       OR Logger_ENABLE_SANITIZER_THREAD
       OR Logger_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    Logger_enable_hardening(Logger_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
