#include "ryzen_hardware.hpp"
#include "profile_catalog.hpp"

#include <windows.h>

#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <ctime>
#include <iomanip>
#include <sstream>

namespace amd_mobile_power {

namespace {

constexpr wchar_t kHardwareOwnerMutex[] =
    L"Local\\AmdMobilePower.HardwareOwner.v1";

std::string WideToUtf8(std::wstring_view value) {
    if (value.empty()) {
        return {};
    }
    const int bytes = WideCharToMultiByte(
        CP_UTF8,
        0,
        value.data(),
        static_cast<int>(value.size()),
        nullptr,
        0,
        nullptr,
        nullptr);
    if (bytes <= 0) {
        return {};
    }
    std::string result(static_cast<std::size_t>(bytes), '\0');
    WideCharToMultiByte(
        CP_UTF8,
        0,
        value.data(),
        static_cast<int>(value.size()),
        result.data(),
        bytes,
        nullptr,
        nullptr);
    return result;
}

std::string UtcTimestamp() {
    const std::time_t now = std::time(nullptr);
    std::tm utc{};
    gmtime_s(&utc, &now);
    std::ostringstream value;
    value << std::put_time(&utc, "%Y-%m-%dT%H:%M:%SZ");
    return value.str();
}

std::string ReadPowerLine() {
    SYSTEM_POWER_STATUS status{};
    if (!GetSystemPowerStatus(&status)) {
        return "unknown";
    }
    if (status.ACLineStatus == 1) {
        return "ac";
    }
    if (status.ACLineStatus == 0) {
        return "battery";
    }
    return "unknown";
}

std::optional<std::string> ReadBiosVersion(void* ryzen_access, int (*get_bios_if_version)(void*)) {
    if (ryzen_access == nullptr || get_bios_if_version == nullptr) {
        return std::nullopt;
    }
    return std::to_string(get_bios_if_version(ryzen_access));
}

struct NativePowerLimitBackend final : IPowerLimitBackend {
    NativePowerLimitBackend(
        void* access,
        int(__stdcall* set_stapm)(void*, std::uint32_t),
        int(__stdcall* set_fast)(void*, std::uint32_t),
        int(__stdcall* set_slow)(void*, std::uint32_t),
        int(__stdcall* refresh)(void*),
        float(__stdcall* get_stapm)(void*),
        float(__stdcall* get_fast)(void*),
        float(__stdcall* get_slow)(void*))
        : ryzen_access(access),
          set_stapm_limit(set_stapm),
          set_fast_limit(set_fast),
          set_slow_limit(set_slow),
          refresh_table(refresh),
          get_stapm_limit(get_stapm),
          get_fast_limit(get_fast),
          get_slow_limit(get_slow) {
    }

    void* ryzen_access = nullptr;
    int(__stdcall* set_stapm_limit)(void*, std::uint32_t) = nullptr;
    int(__stdcall* set_fast_limit)(void*, std::uint32_t) = nullptr;
    int(__stdcall* set_slow_limit)(void*, std::uint32_t) = nullptr;
    int(__stdcall* refresh_table)(void*) = nullptr;
    float(__stdcall* get_stapm_limit)(void*) = nullptr;
    float(__stdcall* get_fast_limit)(void*) = nullptr;
    float(__stdcall* get_slow_limit)(void*) = nullptr;

    int SetStapmLimit(std::uint32_t milliwatts) override {
        return set_stapm_limit == nullptr
            ? -1
            : set_stapm_limit(ryzen_access, milliwatts);
    }

    int SetFastLimit(std::uint32_t milliwatts) override {
        return set_fast_limit == nullptr
            ? -1
            : set_fast_limit(ryzen_access, milliwatts);
    }

    int SetSlowLimit(std::uint32_t milliwatts) override {
        return set_slow_limit == nullptr
            ? -1
            : set_slow_limit(ryzen_access, milliwatts);
    }

    int RefreshTable() override {
        return refresh_table == nullptr ? -1 : refresh_table(ryzen_access);
    }

    static std::optional<double> ReadValue(
        float(__stdcall* function)(void*),
        void* ryzen_access) {
        if (function == nullptr || ryzen_access == nullptr) {
            return std::nullopt;
        }
        const double value = static_cast<double>(function(ryzen_access));
        return std::isfinite(value)
            ? std::optional<double>(value)
            : std::nullopt;
    }

    std::optional<double> GetStapmLimit() override {
        return ReadValue(get_stapm_limit, ryzen_access);
    }

    std::optional<double> GetFastLimit() override {
        return ReadValue(get_fast_limit, ryzen_access);
    }

    std::optional<double> GetSlowLimit() override {
        return ReadValue(get_slow_limit, ryzen_access);
    }
};

}  // namespace

RyzenHardware::RyzenHardware(std::wstring runtime_directory)
    : runtime_directory_(std::move(runtime_directory)) {
}

RyzenHardware::~RyzenHardware() {
    if (ryzen_access_ != nullptr && cleanup_ryzenadj_ != nullptr) {
        cleanup_ryzenadj_(ryzen_access_);
        ryzen_access_ = nullptr;
    }
    if (ols_initialization_attempted_ && deinitialize_ols_ != nullptr) {
        deinitialize_ols_();
    }
    if (hardware_owner_mutex_ != nullptr) {
        CloseHandle(static_cast<HANDLE>(hardware_owner_mutex_));
        hardware_owner_mutex_ = nullptr;
    }
    if (ryzenadj_handle_ != nullptr) {
        FreeLibrary(static_cast<HMODULE>(ryzenadj_handle_));
        ryzenadj_handle_ = nullptr;
    }
    if (inpout_handle_ != nullptr) {
        FreeLibrary(static_cast<HMODULE>(inpout_handle_));
        inpout_handle_ = nullptr;
    }
    if (winring_handle_ != nullptr) {
        FreeLibrary(static_cast<HMODULE>(winring_handle_));
        winring_handle_ = nullptr;
    }
}

bool RyzenHardware::LoadFunction(
    void* module,
    const char* name,
    void** target,
    std::string& error) {
    if (module == nullptr) {
        error = "native library handle is null";
        return false;
    }
    FARPROC address = GetProcAddress(static_cast<HMODULE>(module), name);
    if (address == nullptr) {
        error = std::string("missing RyzenAdj export: ") + name;
        return false;
    }
    *target = reinterpret_cast<void*>(address);
    return true;
}

bool RyzenHardware::Initialize(std::string& error) {
    if (initialized_) {
        return true;
    }
    if (runtime_directory_.empty()) {
        error = "RyzenAdj runtime directory is empty";
        return false;
    }

    SetDllDirectoryW(runtime_directory_.c_str());
    const auto load_library = [&](const wchar_t* name) -> HMODULE {
        const std::wstring path = runtime_directory_ + L"\\" + name;
        return LoadLibraryW(path.c_str());
    };

    winring_handle_ = load_library(L"WinRing0x64.dll");
    inpout_handle_ = load_library(L"inpoutx64.dll");
    ryzenadj_handle_ = load_library(L"libryzenadj.dll");
    if (winring_handle_ == nullptr || inpout_handle_ == nullptr ||
        ryzenadj_handle_ == nullptr) {
        error = "unable to load RyzenAdj runtime DLLs";
        return false;
    }

    if (!LoadFunction(winring_handle_, "GetDllStatus",
            reinterpret_cast<void**>(&get_dll_status_), error) ||
        !LoadFunction(winring_handle_, "InitializeOls",
            reinterpret_cast<void**>(&initialize_ols_), error) ||
        !LoadFunction(winring_handle_, "DeinitializeOls",
            reinterpret_cast<void**>(&deinitialize_ols_), error) ||
        !LoadFunction(ryzenadj_handle_, "init_ryzenadj",
            reinterpret_cast<void**>(&init_ryzenadj_), error) ||
        !LoadFunction(ryzenadj_handle_, "cleanup_ryzenadj",
            reinterpret_cast<void**>(&cleanup_ryzenadj_), error) ||
        !LoadFunction(ryzenadj_handle_, "get_cpu_family",
            reinterpret_cast<void**>(&get_cpu_family_), error) ||
        !LoadFunction(ryzenadj_handle_, "get_bios_if_ver",
            reinterpret_cast<void**>(&get_bios_if_version_), error) ||
        !LoadFunction(ryzenadj_handle_, "init_table",
            reinterpret_cast<void**>(&init_table_), error) ||
        !LoadFunction(ryzenadj_handle_, "refresh_table",
            reinterpret_cast<void**>(&refresh_table_), error) ||
        !LoadFunction(ryzenadj_handle_, "get_table_ver",
            reinterpret_cast<void**>(&get_table_version_), error) ||
        !LoadFunction(ryzenadj_handle_, "set_stapm_limit",
            reinterpret_cast<void**>(&set_stapm_limit_), error) ||
        !LoadFunction(ryzenadj_handle_, "set_fast_limit",
            reinterpret_cast<void**>(&set_fast_limit_), error) ||
        !LoadFunction(ryzenadj_handle_, "set_slow_limit",
            reinterpret_cast<void**>(&set_slow_limit_), error) ||
        !LoadFunction(ryzenadj_handle_, "get_stapm_limit",
            reinterpret_cast<void**>(&get_stapm_limit_), error) ||
        !LoadFunction(ryzenadj_handle_, "get_stapm_value",
            reinterpret_cast<void**>(&get_stapm_value_), error) ||
        !LoadFunction(ryzenadj_handle_, "get_fast_limit",
            reinterpret_cast<void**>(&get_fast_limit_), error) ||
        !LoadFunction(ryzenadj_handle_, "get_fast_value",
            reinterpret_cast<void**>(&get_fast_value_), error) ||
        !LoadFunction(ryzenadj_handle_, "get_slow_limit",
            reinterpret_cast<void**>(&get_slow_limit_), error) ||
        !LoadFunction(ryzenadj_handle_, "get_slow_value",
            reinterpret_cast<void**>(&get_slow_value_), error) ||
        !LoadFunction(ryzenadj_handle_, "get_tctl_temp",
            reinterpret_cast<void**>(&get_tctl_limit_), error) ||
        !LoadFunction(ryzenadj_handle_, "get_tctl_temp_value",
            reinterpret_cast<void**>(&get_tctl_value_), error)) {
        return false;
    }

    hardware_owner_mutex_ = CreateMutexW(
        nullptr,
        TRUE,
        kHardwareOwnerMutex);
    if (hardware_owner_mutex_ == nullptr || GetLastError() == ERROR_ALREADY_EXISTS) {
        error = "another AMD Mobile Power or RyzenAdj hardware owner is active";
        return false;
    }

    // Failed initialization may still allocate driver resources. Clean up
    // after an attempt, but never when ownership checks returned before it.
    ols_initialization_attempted_ = true;
    const int ols_initialized = initialize_ols_();
    const std::uint32_t dll_status = get_dll_status_();
    if (!ols_initialized || dll_status != 0) {
        error = "WinRing0 initialization failed with status " +
            std::to_string(dll_status);
        return false;
    }

    ryzen_access_ = init_ryzenadj_();
    if (ryzen_access_ == nullptr) {
        error = "init_ryzenadj failed";
        return false;
    }
    const int table_result = init_table_(ryzen_access_);
    if (table_result != 0) {
        error = "init_table failed with code " + std::to_string(table_result);
        return false;
    }
    initialized_ = true;
    return true;
}

bool RyzenHardware::IsInitialized() const {
    return initialized_;
}

PlatformCapability RyzenHardware::Probe() {
    PlatformCapability capability;
    capability.cpu.processor_name = ReadProcessorName();
    if (!initialized_ || get_cpu_family_ == nullptr) {
        capability.unsupported_reason = "RyzenAdj hardware backend is not initialized";
        return capability;
    }

    const int family = get_cpu_family_(ryzen_access_);
    capability.cpu.ryzen_adj_family = family;
    capability.cpu.ryzen_adj_family_name = RyzenAdjFamilyName(family);
    capability.cpu.smu_bios_version = ReadBiosVersion(ryzen_access_, get_bios_if_version_);
    if (get_table_version_ != nullptr) {
        std::ostringstream table_version;
        table_version << std::hex << get_table_version_(ryzen_access_);
        capability.cpu.pm_table_version = table_version.str();
    }

    const auto* profile = FindPlatformProfile(
        family,
        capability.cpu.processor_name,
        capability.cpu.pm_table_version.value_or(""));
    if (profile != nullptr) {
        capability.profile = ProfileInfo{
            profile->id,
            profile->display_name,
            profile->minimum_watts,
            profile->maximum_watts,
            profile->default_watts,
            profile->verified,
            profile->family_fallback,
            profile->families};
        capability.limits = LimitCapability{
            profile->supports_stapm,
            profile->supports_fast,
            profile->supports_slow};
        capability.is_supported = true;
    } else {
        capability.unsupported_reason =
            "Unsupported RyzenAdj family: " + std::to_string(family);
    }
    return capability;
}

TelemetrySnapshot RyzenHardware::Refresh(std::string& error) {
    TelemetrySnapshot telemetry;
    if (!initialized_ || refresh_table_ == nullptr || ryzen_access_ == nullptr) {
        error = "RyzenAdj hardware backend is not initialized";
        return telemetry;
    }
    const int refresh_result = refresh_table_(ryzen_access_);
    if (refresh_result != 0) {
        error = "refresh_table failed with code " + std::to_string(refresh_result);
        return telemetry;
    }

    const auto read_value = [&](GetValueFn function) -> std::optional<double> {
        return function == nullptr
            ? std::nullopt
            : std::optional<double>(static_cast<double>(function(ryzen_access_)));
    };
    telemetry.stapm_value_watts = read_value(get_stapm_value_);
    telemetry.fast_value_watts = read_value(get_fast_value_);
    telemetry.slow_value_watts = read_value(get_slow_value_);
    telemetry.stapm_limit_watts = read_value(get_stapm_limit_);
    telemetry.fast_limit_watts = read_value(get_fast_limit_);
    telemetry.slow_limit_watts = read_value(get_slow_limit_);
    telemetry.tctl_value_celsius = read_value(get_tctl_value_);
    telemetry.tctl_limit_celsius = read_value(get_tctl_limit_);
    telemetry.power_line = ReadPowerLine();
    telemetry.updated_at = UtcTimestamp();
    return telemetry;
}

PowerLimitApplicationResult RyzenHardware::ApplyTarget(
    const PowerLimitTarget& target,
    const PlatformCapability& capability) {
    PowerLimitApplicationResult result;
    result.target = target;
    if (!initialized_ || ryzen_access_ == nullptr) {
        result.error = "RyzenAdj hardware backend is not initialized";
        return result;
    }
    if (set_stapm_limit_ == nullptr ||
        set_fast_limit_ == nullptr ||
        set_slow_limit_ == nullptr) {
        result.error = "RyzenAdj write functions are unavailable";
        return result;
    }
    if (!capability.is_supported || !capability.profile) {
        result.error = "The platform has no write-capable profile";
        return result;
    }

    NativePowerLimitBackend backend(
        ryzen_access_,
        set_stapm_limit_,
        set_fast_limit_,
        set_slow_limit_,
        refresh_table_,
        get_stapm_limit_,
        get_fast_limit_,
        get_slow_limit_);
    return ApplyPowerLimitTarget(
        backend,
        target,
        capability.profile->minimum_watts,
        capability.profile->maximum_watts,
        capability.limits.supports_fast,
        capability.limits.supports_slow);
}

std::string RyzenHardware::ReadProcessorName() const {
    HKEY key = nullptr;
    constexpr wchar_t kProcessorPath[] =
        L"HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0";
    if (RegOpenKeyExW(
            HKEY_LOCAL_MACHINE,
            kProcessorPath,
            0,
            KEY_READ,
            &key) != ERROR_SUCCESS) {
        return "AMD processor";
    }
    wchar_t value[256]{};
    DWORD value_size = sizeof(value);
    DWORD value_type = 0;
    const LSTATUS result = RegQueryValueExW(
        key,
        L"ProcessorNameString",
        nullptr,
        &value_type,
        reinterpret_cast<LPBYTE>(value),
        &value_size);
    RegCloseKey(key);
    if (result != ERROR_SUCCESS || value_type != REG_SZ) {
        return "AMD processor";
    }
    return WideToUtf8(value);
}

std::string RyzenAdjFamilyName(int family) {
    switch (family) {
    case -2: return "Waiting for load";
    case -1: return "Unknown";
    case 0: return "Raven";
    case 1: return "Picasso";
    case 2: return "Renoir";
    case 3: return "Cezanne";
    case 4: return "Dali";
    case 5: return "Lucienne";
    case 6: return "Van Gogh";
    case 7: return "Rembrandt";
    case 8: return "Mendocino";
    case 9: return "Phoenix";
    case 10: return "Hawk Point";
    case 11: return "Dragon Range";
    case 12: return "Krackan Point";
    case 13: return "Strix Point";
    case 14: return "Strix Halo";
    case 15: return "Fire Range";
    default: return "Family " + std::to_string(family);
    }
}

}  // namespace amd_mobile_power
