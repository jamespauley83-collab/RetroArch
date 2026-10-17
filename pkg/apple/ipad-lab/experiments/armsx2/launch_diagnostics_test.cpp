#include "common/LabFrontend.h"
#include <cassert>
#include <cstring>
#include <iostream>

using namespace LabFrontend;
alignas(16384) static unsigned char memory[32768];
static unsigned probe_mode, allocation_mode, allocations, releases;
static size_t available, returned;
static bool probe_ok, allocation_ok, valid_mapping;

static bool EnvironmentCallback(unsigned command, void* data)
{
	if (command == 84) { ++releases; return true; }
	assert(command == 83);
	auto& request = *static_cast<Allocation*>(data);
	assert(request.version == 1);
	if (!request.size)
	{
		request.mode = probe_mode;
		request.size = available;
		return probe_ok;
	}
	++allocations;
	request = {1, returned, allocation_mode, memory,
		valid_mapping ? (allocation_mode == 2 ? memory : memory + 16384) : nullptr};
	return allocation_ok;
}

static void Reset()
{
	probe_mode = allocation_mode = 4;
	allocations = releases = 0;
	available = returned = 16384;
	probe_ok = allocation_ok = valid_mapping = true;
}

static void Fails(const char* reason, unsigned expected_allocations)
{
	CodeArena arena;
	ArenaReport report;
	assert(!arena.Prepare(EnvironmentCallback, 16384, &report));
	assert(report.error && std::strstr(report.error, reason));
	assert(report.probe.mode == probe_mode && report.probe.size == available);
	assert(allocations == expected_allocations && !arena.Ready());
	if (expected_allocations)
	{
		assert(report.allocation.mode == allocation_mode);
		assert(report.allocation.size == returned);
		assert(releases == 1);
	}
	else assert(releases == 0);
}

int main()
{
	Reset(); probe_ok = false;
	Fails("API is unavailable", 0);
	Reset(); probe_mode = 0;
	Fails("Enable JIT for this test app", 0);
	for (unsigned mode : {1u, 3u, 5u})
	{
		Reset(); probe_mode = mode;
		Fails("unsupported JIT memory mode", 0);
	}
	Reset(); available = 8192;
	Fails("not enough free JIT arena space", 0);
	Reset(); allocation_ok = false;
	Fails("allocation failed", 1);
	Reset(); allocation_mode = 0;
	Fails("allocation failed", 1);
	Reset(); allocation_mode = 3;
	Fails("invalid JIT arena", 1);
	Reset(); valid_mapping = false;
	Fails("invalid JIT arena", 1);
	Reset(); returned = 8192;
	Fails("invalid JIT arena", 1);
	for (unsigned mode : {2u, 4u})
	{
		Reset(); probe_mode = allocation_mode = mode;
		available = 0; // Unknown capacity is not a failed probe.
		CodeArena arena;
		ArenaReport report;
		assert(!arena.Prepare(nullptr, 16384, &report) && report.error);
		assert(arena.Prepare(EnvironmentCallback, 16384, &report));
		assert(!report.error && report.probe.mode == mode && report.allocation.mode == mode);
		assert(allocations == 1 && releases == 0);
		assert(!arena.Prepare(EnvironmentCallback, 32768, &report));
		assert(std::strstr(report.error, "existing JIT arena is too small"));
		assert(arena.Prepare(EnvironmentCallback, 16384, &report));
		assert(!report.error && allocations == 1);
		assert(arena.Release() && releases == 1);
	}
	std::cout << "Launch failure diagnostics and supported-mode retry tests passed\n";
}
