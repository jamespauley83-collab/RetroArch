#include "LabPrototypeGate.h"
#include <cassert>
#include <cstdarg>
#include <cstring>

static unsigned notifications = 0;
static unsigned logs = 0;
static bool Environment(unsigned command, void* data)
{
    assert(command == RETRO_ENVIRONMENT_SET_MESSAGE);
    const auto* message = static_cast<retro_message*>(data);
    assert(message && message->msg && message->frames > 0);
    assert(std::strstr(message->msg, "gameplay disabled"));
    ++notifications;
    return false; // Unsupported notifications must not permit loading.
}
static void Log(retro_log_level level, const char*, ...)
{
    assert(level == RETRO_LOG_ERROR);
    ++logs;
}
int main()
{
    assert(!LabPrototypeCanLoad(Environment, Log));
    assert(notifications == 1 && logs == 1);
    assert(!LabPrototypeCanLoad(nullptr, nullptr));
    assert(!LabPrototypeCanLoad(Environment, nullptr));
    assert(!LabPrototypeCanLoad(nullptr, Log));
    assert(notifications == 2 && logs == 2);
}
