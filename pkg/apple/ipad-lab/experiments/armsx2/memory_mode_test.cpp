#include "common/LabFrontend.h"
#include "libretro-common/include/libretro.h"
#include <cassert>
#include <iostream>

using namespace LabFrontend;
using u32 = uint32_t;
static_assert(RETRO_EXEC_MEM_MODE_WX_TOGGLE == 3);
alignas(16384) static unsigned char memory[32768];
static unsigned probe_mode, result_mode, allocations, releases;
static void* rx;
static void* rw;
static size_t result_size;
static bool probe_ok, allocation_ok, release_ok;
static bool EnvironmentCallback(unsigned command, void* data)
{
	if (command == RETRO_ENVIRONMENT_EXEC_MEM_FREE)
	{
		assert(static_cast<ReleaseRequest*>(data)->rx == rx);
		++releases;
		return release_ok;
	}
	assert(command == RETRO_ENVIRONMENT_EXEC_MEM_ALLOC);
	auto& request = *static_cast<Allocation*>(data);
	if (!request.size)
	{
		request.mode = probe_mode;
		return probe_ok;
	}
	++allocations;
	request = {1, result_size, result_mode, rx, rw};
	return allocation_ok;
}
static void Reset(unsigned mode)
{
	probe_mode = result_mode = mode;
	rx = memory;
	rw = mode == RETRO_EXEC_MEM_MODE_DUAL_MAP ? memory + 16384 : memory;
	result_size = 16384;
	allocations = releases = 0;
	probe_ok = allocation_ok = release_ok = true;
}

struct CacheCall { bool data; void* address; size_t size; };
static std::vector<CacheCall> cache_calls;
static void sys_dcache_flush(void* address, size_t size)
{
	cache_calls.push_back({true, address, size});
}
static void sys_icache_invalidate(void* address, size_t size)
{
	cache_calls.push_back({false, address, size});
}
namespace HostSys { void FlushInstructionCache(void* address, u32 size); }
// Compile the production Apple cache path with observable cache primitives.
#ifndef __APPLE__
#define __APPLE__
#endif
#define RETROARCH_LAB_ARMSX2_BRIDGE
#include "cache_under_test.inc"

int main()
{
	for (unsigned unsupported : {0u, 1u, 3u, 5u})
	{
		Reset(unsupported);
		assert(!Code.Prepare(EnvironmentCallback, 16384));
		assert(!Code.Ready() && allocations == 0 && releases == 0);
		Reset(RETRO_EXEC_MEM_MODE_DUAL_MAP);
		result_mode = unsupported; // Allocation reply must also be checked.
		assert(!Code.Prepare(EnvironmentCallback, 16384));
		assert(!Code.Ready() && allocations == 1 && releases == 1);
	}
	Reset(RETRO_EXEC_MEM_MODE_DUAL_MAP);
	probe_ok = false;
	assert(!Code.Prepare(EnvironmentCallback, 16384) && allocations == 0);
	for (bool partial : {false, true})
	{
		Reset(RETRO_EXEC_MEM_MODE_DUAL_MAP);
		allocation_ok = false;
		if (!partial) rx = rw = nullptr;
		assert(!Code.Prepare(EnvironmentCallback, 16384));
		assert(!Code.Ready() && releases == (partial ? 1u : 0u));
	}
	for (unsigned mode : {RETRO_EXEC_MEM_MODE_RWX, RETRO_EXEC_MEM_MODE_DUAL_MAP})
	{
		for (unsigned invalid = 0; invalid < 5; ++invalid)
		{
			Reset(mode);
			switch (invalid)
			{
				case 0: result_size = 16383; break;
				case 1: rw = nullptr; break;
				case 2: rx = memory + 1; break;
				case 3: rw = memory + 16385; break;
				case 4: rw = mode == RETRO_EXEC_MEM_MODE_RWX ? memory + 16384 : memory; break;
			}
			assert(!Code.Prepare(EnvironmentCallback, 16384));
			assert(!Code.Ready() && allocations == 1 && releases == 1);
		}
		// Exercise positive and negative dual-map offsets, plus identity RWX.
		for (bool reverse : {false, true})
		{
			Reset(mode);
			if (reverse && mode == RETRO_EXEC_MEM_MODE_DUAL_MAP) std::swap(rx, rw);
			assert(Code.Prepare(EnvironmentCallback, 16384));
			assert(Code.AcquireRX(16384) == rx);
			for (size_t offset : {size_t(0), size_t(12), size_t(16380)})
			{
				cache_calls.clear();
				void* executable = static_cast<unsigned char*>(rx) + offset;
				HostSys::FlushInstructionCache(executable, 4);
				assert(cache_calls.size() == 2);
				assert(cache_calls[0].data && cache_calls[0].address == static_cast<unsigned char*>(rw) + offset);
				assert(!cache_calls[1].data && cache_calls[1].address == executable);
				assert(cache_calls[0].size == 4 && cache_calls[1].size == 4);
			}
			assert(!Code.Release() && releases == 0);
			assert(Code.ReturnRX(rx, 16384));
			release_ok = false;
			assert(!Code.Release() && Code.Ready() && releases == 1);
			release_ok = true;
			assert(Code.Release() && !Code.Ready() && releases == 2);
			assert(Code.Release() && releases == 2);
			assert(!Code.AcquireRX(4) && !Code.WritableForRX(rx, 4));
		}
	}
	std::cout << "Memory mode, allocation failure, cache ordering and release tests passed\n";
}
