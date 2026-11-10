#include "profile_catalog.hpp"

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
        true},
    PlatformProfile{
        "ryzenadj-hawk-point",
        "Hawk Point family profile (unverified)",
        5,
        45,
        15,
        true,
        true,
        true,
        false},
    PlatformProfile{
        "ryzenadj-phoenix",
        "Phoenix family profile (unverified)",
        5,
        45,
        15,
        true,
        true,
        true,
        false},
    PlatformProfile{
        "ryzenadj-rembrandt",
        "Rembrandt family profile (unverified)",
        5,
        45,
        15,
        true,
        true,
        true,
        false},
    PlatformProfile{
        "ryzenadj-renoir-cezanne",
        "Renoir/Cezanne/Lucienne family profile (unverified)",
        5,
        45,
        15,
        true,
        true,
        true,
        false},
    PlatformProfile{
        "ryzenadj-krackan-strix",
        "Krackan/Strix family profile (unverified)",
        5,
        55,
        20,
        true,
        true,
        true,
        false},
    PlatformProfile{
        "ryzenadj-strix-halo",
        "Strix Halo family profile (unverified)",
        5,
        60,
        25,
        true,
        true,
        true,
        false},
    PlatformProfile{
        "ryzenadj-dragon-fire",
        "Dragon/Fire Range family profile (unverified)",
        5,
        65,
        30,
        true,
        true,
        true,
        false},
    PlatformProfile{
        "ryzenadj-mendocino",
        "Mendocino family profile (unverified)",
        5,
        30,
        12,
        true,
        true,
        true,
        false},
    PlatformProfile{
        "ryzenadj-legacy",
        "Legacy Ryzen mobile family profile (unverified)",
        5,
        35,
        15,
        true,
        true,
        true,
        false}};

const PlatformProfile* FindByFamily(int family) {
    switch (family) {
    case 10:
        return &kProfiles[1];
    case 9:
        return &kProfiles[2];
    case 7:
        return &kProfiles[3];
    case 2:
    case 3:
    case 5:
        return &kProfiles[4];
    case 12:
    case 13:
        return &kProfiles[5];
    case 14:
        return &kProfiles[6];
    case 11:
    case 15:
        return &kProfiles[7];
    case 8:
        return &kProfiles[8];
    case 0:
    case 1:
    case 4:
    case 6:
        return &kProfiles[9];
    default:
        return nullptr;
    }
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
