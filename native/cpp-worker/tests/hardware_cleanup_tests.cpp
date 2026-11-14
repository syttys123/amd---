#include "../src/ryzen_hardware.hpp"

#include <iostream>

namespace amd_mobile_power {
struct RyzenHardwareTestAccess {
    static void Configure(RyzenHardware& hardware, bool attempted,
        void(__stdcall* cleanup)()) {
        hardware.ols_initialization_attempted_ = attempted;
        hardware.deinitialize_ols_ = cleanup;
    }
};
}

namespace {
int cleanup_count = 0;
void __stdcall CountCleanup() { ++cleanup_count; }
}

int main() {
    using amd_mobile_power::RyzenHardware;
    using amd_mobile_power::RyzenHardwareTestAccess;
    {
        RyzenHardware hardware(L"");
        RyzenHardwareTestAccess::Configure(hardware, false, CountCleanup);
    }
    if (cleanup_count != 0) {
        std::cerr << "Unattempted OLS initialization triggered cleanup\n";
        return 1;
    }
    {
        RyzenHardware hardware(L"");
        RyzenHardwareTestAccess::Configure(hardware, true, CountCleanup);
    }
    if (cleanup_count != 1) {
        std::cerr << "Attempted OLS initialization must clean up once\n";
        return 1;
    }
    {
        RyzenHardware hardware(L"");
        RyzenHardwareTestAccess::Configure(hardware, true, nullptr);
    }
    if (cleanup_count != 1) { return 1; }
    std::cout << "hardware_cleanup_tests: PASS (no driver loaded)\n";
    return 0;
}
