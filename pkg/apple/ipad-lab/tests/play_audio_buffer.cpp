#include "SH_LibreAudio.h"
#include "ext/libretro.h"
#include <algorithm>
#include <atomic>
#include <cassert>
#include <iostream>
#include <limits>
#include <thread>
#include <vector>

static std::vector<int16> output;
static size_t limit = std::numeric_limits<size_t>::max();
static size_t calls = 0;

static size_t Receive(const int16_t* samples, size_t frames)
{
	++calls;
	const size_t accepted = std::min(limit, frames);
	output.insert(output.end(), samples, samples + accepted * 2);
	return accepted;
}

retro_audio_sample_batch_t g_set_audio_sample_batch_cb = Receive;

int main()
{
	CSH_LibreAudio audio;
	int16 a[] = {1, -1, 2, -2};
	int16 b[] = {3, -3, 4, -4};

	// Multiple VM writes must arrive in order, including partial acceptance.
	audio.Write(a, 4, 44100);
	audio.Write(b, 4, 44100);
	limit = 1;
	audio.ProcessBuffer();
	assert((output == std::vector<int16>{1, -1}));
	limit = 0;
	audio.ProcessBuffer();
	assert(output.size() == 2);
	limit = std::numeric_limits<size_t>::max();
	audio.ProcessBuffer();
	assert((output == std::vector<int16>{1, -1, 2, -2, 3, -3, 4, -4}));
	const auto previousCalls = calls;
	audio.ProcessBuffer();
	assert(calls == previousCalls);

	// Missing callbacks retain data; Reset discards queued audio.
	output.clear();
	g_set_audio_sample_batch_cb = nullptr;
	audio.Write(a, 4, 44100);
	audio.ProcessBuffer();
	g_set_audio_sample_batch_cb = Receive;
	audio.ProcessBuffer();
	assert((output == std::vector<int16>{1, -1, 2, -2}));
	output.clear();
	audio.Write(b, 4, 44100);
	audio.Reset();
	audio.ProcessBuffer();
	assert(output.empty());

	// Backlog is bounded; overflow retains the newest complete stereo frames.
	std::vector<int16> large(44100 * 2 + 4, 7);
	large[large.size() - 2] = 9;
	large[large.size() - 1] = -9;
	audio.Write(large.data(), large.size(), 44100);
	assert(!audio.HasFreeBuffers());
	audio.Write(b, 4, 44100);
	audio.ProcessBuffer();
	assert(output.size() == 44100 * 2);
	assert(output[output.size() - 6] == 9);
	assert(output[output.size() - 5] == -9);
	assert(std::equal(output.end() - 4, output.end(), b));
	assert(audio.HasFreeBuffers());
	output.clear();

	// Ignore invalid/empty input without changing stereo alignment.
	audio.Write(nullptr, 4, 44100);
	audio.Write(a, 0, 44100);
	audio.Write(a, 1, 44100);
	audio.Write(a, 3, 44100);
	audio.ProcessBuffer();
	assert((output == std::vector<int16>{1, -1}));
	output.clear();

	// Exercise the real producer/consumer implementation concurrently.
	std::atomic<bool> done{false};
	std::thread producer([&]() {
		for(unsigned i = 0; i < 20000; ++i) audio.Write(a, 4, 44100);
		done = true;
	});
	while(!done)
	{
		audio.ProcessBuffer();
		std::this_thread::yield();
	}
	producer.join();
	audio.ProcessBuffer();
	assert(output.size() == 80000);
	for(size_t i = 0; i < output.size(); ++i)
		assert(output[i] == a[i % 4]);
	std::cout << "Play! audio buffer checks passed\n";
}
