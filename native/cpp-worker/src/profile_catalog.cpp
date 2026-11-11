#include "profile_catalog.hpp"

#include <algorithm>
#include <array>

namespace amd_mobile_power {

namespace {

const std::array<PlatformProfile, 10> kProfiles{
    PlatformProfile{
        "hawk-point-8845hs",
        "Hawk Point 8845HS development profile",
        5,
        60,
        25,
        true,
        true,
        true,
        true,
        false,
        {10}},
    PlatformProfile{
        "ryzenadj-hawk-point",
        "Hawk Point family profile (unverified)",
        5,
        45,
        15,
        true,
        true,
        true,
        false,
        true,
        {10}},
    PlatformProfile{
        "ryzenadj-phoenix",
        "Phoenix family profile (unverified)",
        5,
        45,
        15,
        true,
        true,
        true,
        false,
        true,
        {9}},
    PlatformProfile{
        "ryzenadj-rembrandt",
        "Rembrandt family profile (unverified)",
        5,
        45,
        15,
        true,
        true,
        true,
        false,
        true,
        {7}},
    PlatformProfile{
        "ryzenadj-renoir-cezanne",
        "Renoir/Cezanne/Lucienne family profile (unverified)",
        5,
        45,
        15,
        true,
        true,
        true,
        false,
        true,
        {2, 3, 5}},
    PlatformProfile{
        "ryzenadj-krackan-strix",
        "Krackan/Strix family profile (unverified)",
        5,
        55,
        20,
        true,
        true,
        true,
        false,
        true,
        {12, 13}},
    PlatformProfile{
        "ryzenadj-strix-halo",
        "Strix Halo family profile (unverified)",
        5,
        60,
        25,
        true,
        true,
        true,
        false,
        true,
        {14}},
    PlatformProfile{
        "ryzenadj-dragon-fire",
        "Dragon/Fire Range family profile (unverified)",
        5,
        65,
        30,
        true,
        true,
        true,
        false,
        true,
        {11, 15}},
    PlatformProfile{
        "ryzenadj-mendocino",
        "Mendocino family profile (unverified)",
        5,
        30,
        12,
        true,
        true,
        true,
        false,
        true,
        {8}},
    PlatformProfile{
        "ryzenadj-legacy",
        "Legacy Ryzen mobile family profile (unverified)",
        5,
        35,
        15,
        true,
        true,
        true,
        false,
        true,
        {0, 1, 4, 6}}};

const PlatformProfile* FindByFamily(int family) {
    for (const auto& profile : kProfiles) {
        if (!profile.family_fallback) {
            continue;
        }
        if (std::find(
                profile.families.begin(),
                profile.families.end(),
                family) != profile.families.end()) {
            return &profile;
        }
    }
    return nullptr;
}

}  // namespace

const PlatformProfile* FindPlatformProfile(
    int family,
    const std::string& processor_name,
    const std::string& pm_table_version) {
    if (family == 10 &&
        processor_name.find("8845HS") != std::string::npos &&
        pm_table_version == "4c0009") {
        return &kProfiles[0];
    }
    return FindByFamily(family);
}

std::vector<const PlatformProfile*> AllPlatformProfiles() {
    std::vector<const PlatformProfile*> profiles;
    profiles.reserve(kProfiles.size());
    for (const auto& profile : kProfiles) {
        profiles.push_back(&profile);
    }
    return profiles;
}

}  // namespace amd_mobile_power
