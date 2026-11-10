#include <windows.h>

#include <algorithm>
#include <chrono>
#include <cctype>
#include <cstdint>
#include <iostream>
#include <sstream>
#include <string>
#include <string_view>
#include <thread>

namespace {

constexpr wchar_t kDefaultPipeName[] =
    L"\\\\.\\pipe\\AmdMobilePower.NativeWorker.v1";
constexpr std::string_view kWorkerVersion = "0.1.0-native";
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

std::string HealthPayload() {
    const auto now = std::chrono::steady_clock::now().time_since_epoch();
    const auto uptime_seconds =
        std::chrono::duration<double>(now).count();
    std::ostringstream payload;
    payload
        << "{\"status\":\"ok\",\"protocolVersion\":1,"
        << "\"workerVersion\":\"" << kWorkerVersion << "\","
        << "\"processId\":" << GetCurrentProcessId() << ","
        << "\"uptimeSeconds\":" << uptime_seconds << ","
        << "\"hardwareInitialized\":false}";
    return payload.str();
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
    for (int index = 1; index < argc; ++index) {
        const std::wstring_view argument = argv[index];
        if (argument == L"--pipe-name") {
            if (index + 1 >= argc) {
                std::wcerr << L"--pipe-name requires a value\n";
                return 2;
            }
            pipe_name = argv[++index];
        } else if (argument == L"--help" || argument == L"-h") {
            std::wcout
                << L"usage: amdmobilepower_native_worker [--pipe-name NAME]\n";
            return 0;
        } else {
            std::wcerr << L"unknown argument\n";
            return 2;
        }
    }

    pipe_name = NormalizePipeName(std::move(pipe_name));

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
                response = SuccessResponse(request.request_id, HealthPayload());
            } else if (request.command == "shutdown") {
                response = SuccessResponse(
                    request.request_id,
                    "{\"status\":\"shutting_down\"}");
                shutdown_requested = true;
            } else {
                response = ErrorResponse(
                    request.request_id,
                    "unsupported_command",
                    "Native worker skeleton only implements getHealth and shutdown.");
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
