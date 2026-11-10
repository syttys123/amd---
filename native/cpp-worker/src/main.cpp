#include <windows.h>

#include "ryzen_hardware.hpp"

#include <algorithm>
#include <chrono>
#include <cctype>
#include <cstdint>
#include <iostream>
#include <iterator>
#include <memory>
#include <optional>
#include <sstream>
#include <string>
#include <string_view>
#include <thread>

namespace {

constexpr wchar_t kDefaultPipeName[] =
    L"\\\\.\\pipe\\AmdMobilePower.NativeWorker.v1";
constexpr std::string_view kWorkerVersion = "0.2.0-native";
constexpr auto kShutdownDelay = std::chrono::milliseconds(150);

struct Request {
    std::string request_id;
    std::string command;
};

struct PipeHandle {
    HANDLE value = INVALID_HANDLE_VALUE;

    PipeHandle() = default;

    ~PipeHandle() {
        if (value != INVALID_HANDLE_VALUE) {
            CloseHandle(value);
        }
    }

    PipeHandle(const PipeHandle&) = delete;
    PipeHandle& operator=(const PipeHandle&) = delete;
};

std::string TrimAscii(std::string value) {
    const auto is_space = [](unsigned char character) {
        return std::isspace(character) != 0;
    };
    value.erase(
        value.begin(),
        std::find_if(value.begin(), value.end(), [&](unsigned char character) {
            return !is_space(character);
        }));
    value.erase(
        std::find_if(value.rbegin(), value.rend(), [&](unsigned char character) {
            return !is_space(character);
        }).base(),
        value.end());
    return value;
}

std::string ExtractJsonString(std::string_view json, std::string_view key) {
    const std::string needle = "\"" + std::string(key) + "\"";
    const std::size_t key_position = json.find(needle);
    if (key_position == std::string_view::npos) {
        return {};
    }

    const std::size_t colon_position = json.find(':', key_position + needle.size());
    if (colon_position == std::string_view::npos) {
        return {};
    }

    const std::size_t quote_start = json.find('"', colon_position + 1);
    if (quote_start == std::string_view::npos) {
        return {};
    }

    std::string value;
    for (std::size_t index = quote_start + 1; index < json.size(); ++index) {
        const char character = json[index];
        if (character == '\\' && index + 1 < json.size()) {
            value.push_back(json[++index]);
            continue;
        }
        if (character == '"') {
            return value;
        }
        value.push_back(character);
    }
    return {};
}

std::string SanitizeJsonString(std::string value) {
    for (char& character : value) {
        const unsigned char current = static_cast<unsigned char>(character);
        if (!std::isalnum(current) && character != '-' && character != '_' &&
            character != '.') {
            character = '_';
        }
    }
    return value.empty() ? "unknown" : value;
}

std::string EscapeJsonString(std::string_view value) {
    std::string escaped;
    escaped.reserve(value.size());
    for (const char character : value) {
        switch (character) {
        case '\\':
        case '"':
            escaped.push_back('\\');
            escaped.push_back(character);
            break;
        case '\n':
            escaped += "\\n";
            break;
        case '\r':
            escaped += "\\r";
            break;
        case '\t':
            escaped += "\\t";
            break;
        default:
            escaped.push_back(character);
            break;
        }
    }
    return escaped;
}

std::string SuccessResponse(
    const std::string& request_id,
    const std::string& payload) {
    std::ostringstream response;
    response
        << "{\"protocolVersion\":1,\"requestId\":\""
        << EscapeJsonString(request_id)
        << "\",\"success\":true,\"payload\":" << payload
        << ",\"error\":null}\n";
    return response.str();
}

std::string ErrorResponse(
    const std::string& request_id,
    std::string_view code,
    std::string_view message) {
    std::ostringstream response;
    response
        << "{\"protocolVersion\":1,\"requestId\":\""
        << EscapeJsonString(request_id)
        << "\",\"success\":false,\"payload\":null,\"error\":{\"code\":\""
        << EscapeJsonString(code) << "\",\"message\":\""
        << EscapeJsonString(message) << "\"}}\n";
    return response.str();
}

std::string HealthPayload(bool hardware_initialized) {
    static const auto started_at = std::chrono::steady_clock::now();
    const auto uptime_seconds = std::chrono::duration<double>(
        std::chrono::steady_clock::now() - started_at).count();
    std::ostringstream payload;
    payload
        << "{\"status\":\"ok\",\"protocolVersion\":1,"
        << "\"workerVersion\":\"" << kWorkerVersion << "\","
        << "\"processId\":" << GetCurrentProcessId() << ","
        << "\"uptimeSeconds\":" << uptime_seconds << ","
        << "\"hardwareInitialized\":"
        << (hardware_initialized ? "true" : "false") << "}";
    return payload.str();
}

void AppendOptionalInt(std::ostringstream& output, const std::optional<int>& value) {
    if (value) {
        output << *value;
    } else {
        output << "null";
    }
}

void AppendOptionalString(
    std::ostringstream& output,
    const std::optional<std::string>& value) {
    if (value) {
        output << '"' << EscapeJsonString(*value) << '"';
    } else {
        output << "null";
    }
}

void AppendOptionalDouble(
    std::ostringstream& output,
    const std::optional<double>& value) {
    if (value) {
        output << *value;
    } else {
        output << "null";
    }
}

std::string PlatformPayload(const amd_mobile_power::PlatformCapability& capability) {
    std::ostringstream output;
    output << "{\"cpu\":{\"processorName\":\""
           << EscapeJsonString(capability.cpu.processor_name)
           << "\",\"vendor\":\""
           << EscapeJsonString(capability.cpu.vendor)
           << "\",\"family\":";
    AppendOptionalInt(output, capability.cpu.family);
    output << ",\"model\":";
    AppendOptionalInt(output, capability.cpu.model);
    output << ",\"ryzenAdjFamily\":";
    AppendOptionalInt(output, capability.cpu.ryzen_adj_family);
    output << ",\"ryzenAdjFamilyName\":";
    AppendOptionalString(output, capability.cpu.ryzen_adj_family_name);
    output << ",\"smuBiosVersion\":";
    AppendOptionalString(output, capability.cpu.smu_bios_version);
    output << ",\"pmTableVersion\":";
    AppendOptionalString(output, capability.cpu.pm_table_version);
    output << "},\"limits\":{\"supportsStapm\":"
           << (capability.limits.supports_stapm ? "true" : "false")
           << ",\"supportsFast\":"
           << (capability.limits.supports_fast ? "true" : "false")
           << ",\"supportsSlow\":"
           << (capability.limits.supports_slow ? "true" : "false")
           << ",\"supportsAny\":"
           << (capability.limits.supports_stapm ||
                       capability.limits.supports_fast ||
                       capability.limits.supports_slow
                   ? "true"
                   : "false")
           << "},\"isSupported\":"
           << (capability.is_supported ? "true" : "false")
           << ",\"unsupportedReason\":";
    AppendOptionalString(output, capability.unsupported_reason);
    output << "}";
    return output.str();
}

std::string CapabilityPayload(
    const amd_mobile_power::PlatformCapability& capability) {
    std::ostringstream output;
    output << "{\"platform\":" << PlatformPayload(capability)
           << ",\"matchedProfile\":null}";
    return output.str();
}

std::string TelemetryPayload(const amd_mobile_power::TelemetrySnapshot& telemetry) {
    std::ostringstream output;
    output << "{\"targetWatts\":";
    AppendOptionalDouble(output, telemetry.target_watts);
    output << ",\"stapmValueWatts\":";
    AppendOptionalDouble(output, telemetry.stapm_value_watts);
    output << ",\"fastValueWatts\":";
    AppendOptionalDouble(output, telemetry.fast_value_watts);
    output << ",\"slowValueWatts\":";
    AppendOptionalDouble(output, telemetry.slow_value_watts);
    output << ",\"stapmLimitWatts\":";
    AppendOptionalDouble(output, telemetry.stapm_limit_watts);
    output << ",\"fastLimitWatts\":";
    AppendOptionalDouble(output, telemetry.fast_limit_watts);
    output << ",\"slowLimitWatts\":";
    AppendOptionalDouble(output, telemetry.slow_limit_watts);
    output << ",\"tctlValueCelsius\":";
    AppendOptionalDouble(output, telemetry.tctl_value_celsius);
    output << ",\"tctlLimitCelsius\":";
    AppendOptionalDouble(output, telemetry.tctl_limit_celsius);
    output << ",\"powerLine\":\"" << EscapeJsonString(telemetry.power_line)
           << "\",\"updatedAt\":";
    AppendOptionalString(output, telemetry.updated_at);
    output << ",\"hasFirmwareClamp\":"
           << (telemetry.has_firmware_clamp ? "true" : "false") << "}";
    return output.str();
}

std::string SnapshotPayload(
    const amd_mobile_power::PlatformCapability& capability,
    const amd_mobile_power::TelemetrySnapshot& telemetry) {
    std::ostringstream output;
    output << "{\"platform\":" << PlatformPayload(capability)
           << ",\"matchedProfile\":null,\"telemetry\":"
           << TelemetryPayload(telemetry) << "}";
    return output.str();
}

bool WriteAll(HANDLE pipe, std::string_view value) {
    std::size_t offset = 0;
    while (offset < value.size()) {
        DWORD written = 0;
        const DWORD remaining =
            static_cast<DWORD>(value.size() - offset);
        if (!WriteFile(
                pipe,
                value.data() + offset,
                remaining,
                &written,
                nullptr)) {
            return false;
        }
        if (written == 0) {
            return false;
        }
        offset += written;
    }
    return true;
}

Request ParseRequest(std::string_view line) {
    Request request;
    request.request_id =
        SanitizeJsonString(ExtractJsonString(line, "requestId"));
    request.command = TrimAscii(ExtractJsonString(line, "command"));
    return request;
}

std::wstring NormalizePipeName(std::wstring value) {
    constexpr std::wstring_view prefix = L"\\\\.\\pipe\\";
    if (value.starts_with(prefix)) {
        return value;
    }
    return std::wstring(prefix) + value;
}

}  // namespace

int wmain(int argc, wchar_t* argv[]) {
    std::wstring pipe_name = kDefaultPipeName;
    std::wstring ryzenadj_directory;
    bool enable_hardware = false;
    for (int index = 1; index < argc; ++index) {
        const std::wstring_view argument = argv[index];
        if (argument == L"--pipe-name") {
            if (index + 1 >= argc) {
                std::wcerr << L"--pipe-name requires a value\n";
                return 2;
            }
            pipe_name = argv[++index];
        } else if (argument == L"--ryzenadj-dir") {
            if (index + 1 >= argc) {
                std::wcerr << L"--ryzenadj-dir requires a value\n";
                return 2;
            }
            ryzenadj_directory = argv[++index];
        } else if (argument == L"--enable-hardware") {
            enable_hardware = true;
        } else if (argument == L"--help" || argument == L"-h") {
            std::wcout
                << L"usage: amdmobilepower_native_worker [--pipe-name NAME] "
                   L"[--ryzenadj-dir DIRECTORY] [--enable-hardware]\n";
            return 0;
        } else {
            std::wcerr << L"unknown argument\n";
            return 2;
        }
    }

    pipe_name = NormalizePipeName(std::move(pipe_name));

    std::unique_ptr<amd_mobile_power::RyzenHardware> hardware;
    if (enable_hardware) {
        if (ryzenadj_directory.empty()) {
            wchar_t executable_path[MAX_PATH]{};
            if (GetModuleFileNameW(
                    nullptr,
                    executable_path,
                    static_cast<DWORD>(std::size(executable_path))) == 0) {
                std::wcerr << L"GetModuleFileNameW failed\n";
                return 3;
            }
            std::wstring executable(executable_path);
            const std::size_t separator = executable.find_last_of(L"\\/");
            ryzenadj_directory = separator == std::wstring::npos
                ? L"."
                : executable.substr(0, separator);
        }
        hardware = std::make_unique<amd_mobile_power::RyzenHardware>(
            ryzenadj_directory);
        std::string hardware_error;
        if (!hardware->Initialize(hardware_error)) {
            std::wcerr << L"RyzenAdj initialization failed: ";
            std::wcerr << std::wstring(
                hardware_error.begin(),
                hardware_error.end()) << L"\n";
            return 3;
        }
    }

    PipeHandle pipe;
    pipe.value = CreateNamedPipeW(
        pipe_name.c_str(),
        PIPE_ACCESS_DUPLEX | FILE_FLAG_FIRST_PIPE_INSTANCE,
        PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT,
        1,
        8192,
        8192,
        0,
        nullptr);
    if (pipe.value == INVALID_HANDLE_VALUE) {
        std::wcerr << L"CreateNamedPipeW failed: " << GetLastError() << L"\n";
        return 1;
    }

    bool shutdown_requested = false;
    while (!shutdown_requested) {
        const BOOL connected =
            ConnectNamedPipe(pipe.value, nullptr) != FALSE ||
            GetLastError() == ERROR_PIPE_CONNECTED;
        if (!connected) {
            std::wcerr << L"ConnectNamedPipe failed: " << GetLastError() << L"\n";
            return 1;
        }

        std::string request_line;
        char buffer[1024];
        bool complete_line = false;
        while (!complete_line) {
            DWORD bytes_read = 0;
            if (!ReadFile(
                    pipe.value,
                    buffer,
                    sizeof(buffer),
                    &bytes_read,
                    nullptr)) {
                if (GetLastError() == ERROR_MORE_DATA) {
                    continue;
                }
                break;
            }
            if (bytes_read == 0) {
                break;
            }
            request_line.append(buffer, bytes_read);
            const std::size_t newline = request_line.find('\n');
            if (newline != std::string::npos) {
                request_line.resize(newline);
                complete_line = true;
            }
        }

        if (complete_line) {
            const Request request = ParseRequest(request_line);
            std::string response;
            if (request.command == "getHealth") {
                response = SuccessResponse(
                    request.request_id,
                    HealthPayload(hardware && hardware->IsInitialized()));
            } else if (
                request.command == "getCapabilities" ||
                request.command == "getSnapshot") {
                if (!hardware || !hardware->IsInitialized()) {
                    response = ErrorResponse(
                        request.request_id,
                        "hardware_unavailable",
                        "The native worker was started without --enable-hardware.");
                } else {
                    const auto capability = hardware->Probe();
                    if (request.command == "getCapabilities") {
                        response = SuccessResponse(
                            request.request_id,
                            CapabilityPayload(capability));
                    } else {
                        std::string refresh_error;
                        const auto telemetry = hardware->Refresh(refresh_error);
                        response = refresh_error.empty()
                            ? SuccessResponse(
                                  request.request_id,
                                  SnapshotPayload(capability, telemetry))
                            : ErrorResponse(
                                  request.request_id,
                                  "refresh_failed",
                                  refresh_error);
                    }
                }
            } else if (request.command == "shutdown") {
                response = SuccessResponse(
                    request.request_id,
                    "{\"status\":\"shutting_down\"}");
                shutdown_requested = true;
            } else {
                response = ErrorResponse(
                    request.request_id,
                    "unsupported_command",
                    "Native worker implements getHealth, getCapabilities, getSnapshot, and shutdown.");
            }
            if (!WriteAll(pipe.value, response)) {
                std::wcerr << L"WriteFile failed: " << GetLastError() << L"\n";
            }
            FlushFileBuffers(pipe.value);
        }

        DisconnectNamedPipe(pipe.value);
        if (shutdown_requested) {
            std::this_thread::sleep_for(kShutdownDelay);
        }
    }

    return 0;
}
