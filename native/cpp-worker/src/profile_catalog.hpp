#pragma once

#include <string>
#include <vector>

namespace amd_mobile_power {

struct PlatformProfile {
    std::string id;
    std::string display_name;
    int minimum_watts = 5;
    int maximum_watts = 45;
    int default_watts = 15;
    bool supports_stapm = true;
    bool supports_fast = true;
    bool supports_slow = true;
    bool verified = false;
};

const PlatformProfile* FindPlatformProfile(
    int family,
    const std::string& processor_name,
    const std::string& pm_table_version);

std::vector<const PlatformProfile*> AllPlatformProfiles();

}  // namespace amd_mobile_power
