cmake_minimum_required(VERSION 3.21)
project(amdmobilepower_native_worker LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_executable(amdmobilepower_native_worker
    src/main.cpp
    src/power_limit_policy.cpp
    src/profile_catalog.cpp
    src/ryzen_hardware.cpp
)

add_executable(amdmobilepower_power_limit_policy_tests
    tests/power_limit_policy_tests.cpp
    src/power_limit_policy.cpp
    src/profile_catalog.cpp
)

target_compile_definitions(amdmobilepower_native_worker PRIVATE
    UNICODE
    _UNICODE
)

target_compile_options(amdmobilepower_native_worker PRIVATE
    /W4
    /permissive-
    /utf-8
)

target_compile_options(amdmobilepower_power_limit_policy_tests PRIVATE
    /W4
    /permissive-
    /utf-8
)

target_link_libraries(amdmobilepower_native_worker PRIVATE
    advapi32
)
