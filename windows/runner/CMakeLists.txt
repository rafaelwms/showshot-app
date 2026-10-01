cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "shoshot_native.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# C++/WinRT (used for OCR, below) pulls in coroutine support; this SDK's STL
# rejects the pre-C++20 </experimental/coroutine> path apply_standard_settings'
# cxx_std_17 would otherwise select, so bump just this target to C++20.
target_compile_features(${BINARY_NAME} PUBLIC cxx_std_20)

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "shcore.lib" "shell32.lib" "ole32.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# --- C++/WinRT projection headers, for OCR (Windows.Media.Ocr) ---
#
# These aren't checked in (see windows/.gitignore: cppwinrt_generated/) —
# they're ~85MB of SDK-derived impl headers, the same "platform projection"
# cache a Microsoft.Windows.CppWinRT NuGet install would generate. Generated
# once per checkout, here, by locating the installed Windows SDK's
# cppwinrt.exe + Windows.winmd metadata (both ship with the SDK, no NuGet
# needed) and running it restricted to the namespaces OCR actually needs.
set(CPPWINRT_GENERATED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/cppwinrt_generated")
if(NOT EXISTS "${CPPWINRT_GENERATED_DIR}/winrt/Windows.Media.Ocr.h")
  set(_SDK_ROOT "$ENV{ProgramFiles\(x86\)}/Windows Kits/10")
  file(GLOB _SDK_VERSION_DIRS LIST_DIRECTORIES true "${_SDK_ROOT}/Include/10.0.*")
  if(_SDK_VERSION_DIRS)
    list(SORT _SDK_VERSION_DIRS)
    list(REVERSE _SDK_VERSION_DIRS)
    list(GET _SDK_VERSION_DIRS 0 _SDK_VERSION_PATH)
    get_filename_component(_SDK_VERSION "${_SDK_VERSION_PATH}" NAME)
    find_program(CPPWINRT_EXE cppwinrt
      PATHS "${_SDK_ROOT}/bin/${_SDK_VERSION}/x64" "${_SDK_ROOT}/bin/${_SDK_VERSION}/x86"
            "${_SDK_ROOT}/bin/${_SDK_VERSION}/arm64"
    )
    set(_WINMD "${_SDK_ROOT}/UnionMetadata/${_SDK_VERSION}/Windows.winmd")
    if(CPPWINRT_EXE AND EXISTS "${_WINMD}")
      # Not namespace-restricted via -include: a restricted generation left
      # IVectorView<OcrLine>'s begin()/end() impl undefined at the point of
      # use (some cross-namespace impl headers only get emitted for the full
      # closure). The full projection is ~85MB but only ever generated once.
      message(STATUS "Generating C++/WinRT projection headers for OCR support (one-time, ~85MB)...")
      execute_process(
        COMMAND "${CPPWINRT_EXE}" -input "${_WINMD}" -output "${CPPWINRT_GENERATED_DIR}"
        RESULT_VARIABLE _CPPWINRT_RESULT
      )
      if(NOT _CPPWINRT_RESULT EQUAL 0)
        message(WARNING "cppwinrt.exe failed (${_CPPWINRT_RESULT}); OCR will report 'not implemented' at runtime.")
      endif()
    else()
      message(WARNING "Windows SDK cppwinrt.exe/Windows.winmd not found; OCR will report 'not implemented' at runtime.")
    endif()
  endif()
endif()
if(EXISTS "${CPPWINRT_GENERATED_DIR}/winrt/Windows.Media.Ocr.h")
  target_include_directories(${BINARY_NAME} PRIVATE "${CPPWINRT_GENERATED_DIR}")
  target_link_libraries(${BINARY_NAME} PRIVATE "windowsapp.lib")
  target_compile_definitions(${BINARY_NAME} PRIVATE "SHOSHOT_HAS_WINRT_OCR=1")
endif()

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
