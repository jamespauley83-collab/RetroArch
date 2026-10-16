#include "common/LabFrontend.h"
#include <atomic>
#include <cassert>
#include <cstring>
#include <iostream>
#include <thread>

using namespace LabFrontend;
alignas(16384) static unsigned char memory[32768];
static unsigned mode = 4;
static size_t limit = sizeof(memory) / 2;
static bool malformed = false, fail = false;
static unsigned allocations = 0, frees = 0;
static bool EnvironmentCallback(unsigned command, void* data)
{
	if (command == 84)
	{
		assert(static_cast<ReleaseRequest*>(data)->rx == memory);
		++frees;
		return true;
	}
	assert(command == 83);
	auto& request = *static_cast<Allocation*>(data);
	assert(request.version == 1);
	request.mode = mode;
	if (!request.size) { request.size = limit; return true; }
	++allocations;
	request.rx = memory;
	request.rw = malformed ? nullptr : (mode == 4 ? memory + 16384 : memory);
	return !fail;
}

int main()
{
	CodeArena arena;
	assert(!arena.Prepare(nullptr, 16384));
	for (unsigned unsupported : {0u, 1u, 3u, 5u})
	{
		mode = unsupported;
		assert(!arena.Prepare(EnvironmentCallback, 16384));
	}
	assert(allocations == 0);
	mode = 4;
	assert(!arena.Prepare(EnvironmentCallback, 32768));
	assert(allocations == 0);
	malformed = true;
	assert(!arena.Prepare(EnvironmentCallback, 16384));
	assert(frees == 1 && !arena.Ready());
	malformed = false;
	fail = true;
	assert(!arena.Prepare(EnvironmentCallback, 16384));
	assert(frees == 2);
	fail = false;
	assert(arena.Prepare(EnvironmentCallback, 16384));
	assert(arena.RX(16384) == memory && arena.RW() == memory + 16384);
	assert(arena.RX(32768) == nullptr && arena.Offset() == 16384);
	unsigned before = allocations;
	assert(arena.Prepare(EnvironmentCallback, 16384));
	assert(allocations == before);
	arena.Release();
	arena.Release();
	assert(frees == 3 && !arena.Ready());
	mode = 2;
	assert(arena.Prepare(EnvironmentCallback, 16384));
	assert(arena.RX(16384) == arena.RW() && arena.Offset() == 0);
	arena.Release();
	assert(frees == 4);

	FrameMailbox mailbox;
	Frame output;
	assert(!mailbox.Consume(output));
	assert(!mailbox.Publish({641, 1, {1}}));
	assert(!mailbox.Publish({1, 2, {1}}));
	assert(mailbox.Publish({2, 2, {0xff0000ff, 0xff00ff00, 0xffff0000, 0xff123456}}));
	assert(mailbox.Consume(output));
	assert((output.pixels == std::vector<uint32_t>{0xff0000, 0x00ff00, 0x0000ff, 0x563412}));
	assert(!mailbox.Consume(output));
	assert(mailbox.Publish({1, 1, {0xff000001}}));
	assert(mailbox.Publish({1, 1, {0xff000002}}));
	assert(mailbox.Consume(output) && output.pixels[0] == 0x020000);
	assert(mailbox.Publish({1, 1, {0}}));
	mailbox.Clear();
	assert(!mailbox.Consume(output));

	std::atomic<bool> done{false};
	std::thread producer([&] {
		for (unsigned i = 1; i <= 10000; ++i)
			assert(mailbox.Publish({2, 1, {i, i}}));
		done.store(true);
	});
	while (!done.load())
		if (mailbox.Consume(output))
			assert(output.width == 2 && output.pixels[0] == output.pixels[1]);
	producer.join();
	mailbox.Clear();
	assert(!mailbox.Consume(output));
	std::cout << "JIT ownership/modes and frame transport tests passed\n";
}
