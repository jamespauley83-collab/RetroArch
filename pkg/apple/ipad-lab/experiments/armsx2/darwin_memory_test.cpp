#include "common/LabFrontend.h"
#include <cassert>
#include <cstdio>
#include <iostream>
#include <thread>

namespace DarwinMisc
{
ptrdiff_t g_code_rw_offset = 0;
uintptr_t g_code_rw_base = 0;
size_t g_code_rw_size = 0;
void* MmapCodeDualMap(size_t size);
void MunmapCodeDualMap(void* address, size_t size);
}
static std::mutex s_jit_validation_mutex;
namespace SysMemory { void Reset(); }
static unsigned resets = 0;
static void memReset() { ++resets; }
static void iopMemReset() { ++resets; }
static void vuMemReset() { ++resets; }
enum { Color_StrongBlue };
struct { void WriteLn(int, const char*) {} } DevCon;

// Actual patched Darwin map/unmap and upstream SysMemory::Reset bodies.
#define RETROARCH_LAB_ARMSX2_BRIDGE
#include "memory_under_test.inc"

alignas(16384) static unsigned char memory[32768];
static bool fail = false;
static unsigned frees = 0;
static bool Environment(unsigned command, void* data)
{
	if (command == 84)
	{
		assert(static_cast<LabFrontend::ReleaseRequest*>(data)->rx == memory);
		++frees;
		return true;
	}
	assert(command == 83);
	auto& request = *static_cast<LabFrontend::Allocation*>(data);
	request.mode = 4;
	if (!request.size) { request.size = 16384; return true; }
	if (fail) return false;
	request.rx = memory;
	request.rw = memory + 16384;
	return true;
}

int main()
{
	using namespace DarwinMisc;
	assert(!MmapCodeDualMap(16384));
	fail = true;
	assert(!LabFrontend::Code.Prepare(Environment, 16384));
	assert(!MmapCodeDualMap(16384) && frees == 0);
	fail = false;
	assert(LabFrontend::Code.Prepare(Environment, 16384));
	assert(!MmapCodeDualMap(0) && !MmapCodeDualMap(16385));
	assert(MmapCodeDualMap(16384) == memory);
	const auto check_owner = [] {
		assert(g_code_rw_offset == 16384);
		assert(g_code_rw_base == reinterpret_cast<uintptr_t>(memory + 16384));
		assert(g_code_rw_size == 16384);
	};
	check_owner();
	assert(!MmapCodeDualMap(8) && !MmapCodeDualMap(16384));
	MunmapCodeDualMap(nullptr, 16384);
	MunmapCodeDualMap(memory + 1, 16384);
	MunmapCodeDualMap(memory, 8);
	check_owner();
	assert(!LabFrontend::Code.Release() && frees == 0);
	// VM reset clears data/code caches without returning the code reservation.
	SysMemory::Reset();
	assert(resets == 3 && !MmapCodeDualMap(16384));
	check_owner();
	MunmapCodeDualMap(memory, 16384);
	assert(g_code_rw_offset == 0 && g_code_rw_base == 0 && g_code_rw_size == 0);
	assert(LabFrontend::Code.Ready() && frees == 0);
	MunmapCodeDualMap(memory, 16384);
	// Two simultaneous VM requests can have only one owner.
	void* first = nullptr;
	void* second = nullptr;
	std::thread one([&] { first = MmapCodeDualMap(16384); });
	std::thread two([&] { second = MmapCodeDualMap(16384); });
	one.join();
	two.join();
	assert((first == memory && !second) || (!first && second == memory));
	check_owner();
	MunmapCodeDualMap(memory, 16384);
	assert(LabFrontend::Code.Release() && frees == 1);
	assert(!MmapCodeDualMap(16384));
	assert(LabFrontend::Code.Release() && frees == 1);
	assert(LabFrontend::Code.Prepare(Environment, 16384));
	assert(MmapCodeDualMap(16384) == memory);
	MunmapCodeDualMap(memory, 16384);
	assert(LabFrontend::Code.Release() && frees == 2);
	std::cout << "Darwin ownership, memory reset, teardown and failure tests passed\n";
}
