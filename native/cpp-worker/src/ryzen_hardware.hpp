#pragma once

#include <cstdint>
#include <optional>
#include <string>

namespace amd_mobile_power {

struct PlatformInfo {
    std::string processor_name;
    std::string vendor = "AuthenticAMD";
    std::optional<int> family;
    std::optional<int> model;
    std::optional<int> ryzen_adj_family;
    std::optional<std::string> ryzen_adj_family_name;
    std::optional<std::string> smu_bios_version;
    std::optional<std::string> pm_table_version;
};

struct LimitCapability {
    bool supports_stapm = false;
    bool supports_fast = false;
    bool supports_slow = false;
};

struct PlatformCapability {
    PlatformInfo cpu;
    LimitCapability limits;
    bool is_supported = false;
    std::optional<std::string> unsupported_reason;
};

struct TelemetrySnapshot {
    std::optional<double> target_watts;
    std::optional<double> stapm_value_watts;
    std::optional<double> fast_value_watts;
    std::optional<double> slow_value_watts;
    std::optional<double> stapm_limit_watts;
    std::optional<double> fast_limit_watts;
    std::optional<double> slow_limit_watts;
    std::optional<double> tctl_value_celsius;
    std::optional<double> tctl_limit_celsius;
    std::string power_line = "unknown";
    std::optional<std::string> updated_at;
    bool has_firmware_clamp = false;
};

class RyzenHardware {
public:
    explicit RyzenHardware(std::wstring runtime_directory);
    ~RyzenHardware();

    RyzenHardware(const RyzenHardware&) = delete;
    RyzenHardware& operator=(const RyzenHardware&) = delete;

    bool Initialize(std::string& error);
    bool IsInitialized() const;
    PlatformCapability Probe();
    TelemetrySnapshot Refresh(std::string& error);

private:
    std::wstring runtime_directory_;
    void* winring_handle_ = nullptr;
    void* inpout_handle_ = nullptr;
    void* ryzenadj_handle_ = nullptr;
    void* hardware_owner_mutex_ = nullptr;
    void* ryzen_access_ = nullptr;
    bool initialized_ = false;

    using GetDllStatusFn = std::uint32_t(__stdcall*)();
    using InitializeOlsFn = int(__stdcall*)();
    using DeinitializeOlsFn = void(__stdcall*)();
    using InitRyzenAdjFn = void*(__stdcall*)();
    using CleanupRyzenAdjFn = void(__stdcall*)(void*);
    using GetCpuFamilyFn = int(__cdecl*)(void*);
    using GetBiosIfVersionFn = int(__cdecl*)(void*);
    using InitTableFn = int(__stdcall*)(void*);
    using RefreshTableFn = int(__stdcall*)(void*);
    using GetTableVersionFn = std::uint32_t(__stdcall*)(void*);
    using GetValueFn = float(__stdcall*)(void*);

    GetDllStatusFn get_dll_status_ = nullptr;
    InitializeOlsFn initialize_ols_ = nullptr;
    DeinitializeOlsFn deinitialize_ols_ = nullptr;
    InitRyzenAdjFn init_ryzenadj_ = nullptr;
    CleanupRyzenAdjFn cleanup_ryzenadj_ = nullptr;
    GetCpuFamilyFn get_cpu_family_ = nullptr;
    GetBiosIfVersionFn get_bios_if_version_ = nullptr;
    InitTableFn init_table_ = nullptr;
    RefreshTableFn refresh_table_ = nullptr;
    GetTableVersionFn get_table_version_ = nullptr;
    GetValueFn get_stapm_limit_ = nullptr;
    GetValueFn get_stapm_value_ = nullptr;
    GetValueFn get_fast_limit_ = nullptr;
    GetValueFn get_fast_value_ = nullptr;
    GetValueFn get_slow_limit_ = nullptr;
    GetValueFn get_slow_value_ = nullptr;
    GetValueFn get_tctl_limit_ = nullptr;
    GetValueFn get_tctl_value_ = nullptr;

    bool LoadFunction(void* module, const char* name, void** target, std::string& error);
    std::string ReadProcessorName() const;
};

std::string RyzenAdjFamilyName(int family);

}  // namespace amd_mobile_power
