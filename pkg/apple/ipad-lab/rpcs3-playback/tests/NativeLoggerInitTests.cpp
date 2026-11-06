#include "util/logs.hpp"
#include "RPCS3IOS.h"
#include <atomic>
#include <chrono>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <stdexcept>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

// Production severity, registration, routing, startup buffering, set_init,
// and native callback forwarding are included unchanged. Test adapters replace
// the OS prefix/clock hooks, shared_mutex and no-argument formatting transport.
thread_local std::string (*g_tls_log_prefix)() = [] { return std::string{}; };
thread_local void (*g_tls_log_control)(const char*, u64) = [](const char*, u64) {};
#include "StringViewFormatter.inc"
namespace fmt
{
void raw_append(std::string& out, const char* text, const fmt_type_info* types, const u64*) noexcept
{
    if (types && types->fmt_string) std::abort();
    out.append(text);
}
}
namespace logs
{
#include "LoggerRegistry.inc"
std::mutex g_mutex;
atomic_t<bool> g_init{false};
static u64 get_stamp()
{
    return static_cast<u64>(std::chrono::steady_clock::now().time_since_epoch().count());
}
#include "LoggerSetInit.inc"
}
#include "LoggerDispatch.inc"

struct captured_line
{
    int32_t level;
    std::string text;
};
struct recording_transport
{
    std::mutex mutex;
    std::vector<captured_line> lines;
};
static recording_transport transport;
static rpcs3_ios_config g_config{};
#include "NativeEmitLog.inc"
#include "NativeListener.inc"
static std::unique_ptr<callback_log_listener> g_log_listener;
static void initialize_original()
{
#include "OriginalInit.inc"
}
static void initialize_fixed()
{
#include "FixedInit.inc"
}
static void record(void* context, int32_t level, const char* text)
{
    auto& destination = *static_cast<recording_transport*>(context);
    std::lock_guard lock(destination.mutex);
    destination.lines.push_back({level, text});
}
static void require(bool condition, const char* reason)
{
    if (!condition) throw std::runtime_error(reason);
}
int main(int argc, char** argv)
{
    static logs::channel channel{"native-logger-init-test"};
    logs::registerer registration{channel};
    g_config.log_callback = record;
    g_config.user_context = &transport;
    int result = 0;
    try
    {
        channel.notice("startup notice");
        channel.warning("startup warning");
        channel.error("startup error");
        require(logs::get_logger()->messages.size() == 3, "startup messages must enter the production pending buffer");
        require(transport.lines.empty(), "no listener exists before native initialization");
        if (argc == 2 && std::strcmp(argv[1], "original") == 0) initialize_original();
        else initialize_fixed();
        require(logs::g_init, "native initialization must finalize logging");
        require(logs::get_logger()->messages.empty(), "native initialization must clear the pending buffer");
        require(transport.lines.size() == 3, "startup messages must be delivered exactly once");
        require(transport.lines[0].level == 6 && transport.lines[0].text == "startup notice", "notice severity/text must reach the host callback");
        require(transport.lines[1].level == 5 && transport.lines[1].text == "startup warning", "warning severity/text must reach the host callback");
        require(transport.lines[2].level == 2 && transport.lines[2].text == "startup error", "error severity/text must reach the host callback");
        channel.notice("runtime notice");
        require(transport.lines.size() == 4 && logs::get_logger()->messages.empty(), "runtime messages must be delivered once without being retained");
        logs::set_init({});
        require(transport.lines.size() == 4, "repeated finalization must not replay delivered messages");
        std::vector<std::thread> threads;
        for (int index = 0; index < 4; ++index)
            threads.emplace_back([&] { for (int i = 0; i < 5000; ++i) channel.notice("concurrent runtime notice"); });
        for (auto& thread : threads) thread.join();
        require(transport.lines.size() == 20004, "concurrent runtime callbacks must be delivered exactly once");
        require(logs::get_logger()->messages.empty(), "concurrent runtime logging must not grow the startup buffer");
        logs::set_init({});
        require(transport.lines.size() == 20004, "finalization after runtime logging must remain idempotent");
        std::puts("PASS: production startup replay, native notice/warning/error forwarding, idempotent init and 20000 concurrent messages without startup retention");
    }
    catch (const std::exception& error)
    {
        std::fprintf(stderr, "FAIL: %s\n", error.what());
        result = 1;
    }
    logs::listener::shutdown_all();
    g_log_listener.reset();
    return result;
}
