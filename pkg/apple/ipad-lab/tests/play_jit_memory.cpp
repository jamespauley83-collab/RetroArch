#include <cassert>
#include <cstdio>
#include <cstring>
#include <memory>
#include <thread>
#include <vector>
#include <sys/mman.h>
#include <unistd.h>
#include "PlayJitMemory.h"

static void* rx;
static void* rw;
static size_t page;
static unsigned mode = RETRO_EXEC_MEM_MODE_DUAL_MAP;
static bool supported = true;
static bool legacy = false;
static bool failAllocation = false;
static bool malformed = false;
static unsigned allocations = 0;
static unsigned releases = 0;

static bool Environment(unsigned command, void* data)
{
    if(command == RETRO_ENVIRONMENT_GET_JIT_CAPABLE)
    {
        *static_cast<bool*>(data) = legacy;
        return true;
    }
    if(command == RETRO_ENVIRONMENT_EXEC_MEM_FREE)
    {
        assert(static_cast<retro_exec_mem_free*>(data)->rx == rx);
        releases++;
        return true;
    }
    assert(command == RETRO_ENVIRONMENT_EXEC_MEM_ALLOC);
    if(!supported) return false;
    auto request = static_cast<retro_exec_mem_alloc*>(data);
    assert(request->version == 1);
    request->mode = mode;
    if(request->size)
    {
        if(failAllocation) return false;
        assert(request->size <= page);
        allocations++;
        request->rx = rx;
        request->rw = malformed ? nullptr : rw;
    }
    request->size = page;
    return true;
}

int main()
{
    page = static_cast<size_t>(sysconf(_SC_PAGESIZE));
    auto file = tmpfile();
    assert(file && ftruncate(fileno(file), page) == 0);
    int protection = PROT_READ;
#if defined(__linux__) && defined(__x86_64__)
    protection |= PROT_EXEC;
#endif
    rx = mmap(nullptr, page, protection, MAP_SHARED, fileno(file), 0);
    rw = mmap(nullptr, page, PROT_READ | PROT_WRITE, MAP_SHARED, fileno(file), 0);
    assert(rx != MAP_FAILED && rw != MAP_FAILED && rx != rw);

    CPlayJitMemory jit;
    mode = RETRO_EXEC_MEM_MODE_UNAVAILABLE;
    legacy = true;
    assert(!jit.Prepare(Environment));
    legacy = false;
    mode = RETRO_EXEC_MEM_MODE_DUAL_MAP;
    failAllocation = true;
    assert(!jit.Prepare(Environment));
    failAllocation = false;
    malformed = true;
    assert(!jit.Prepare(Environment));
    assert(releases == 1);
    malformed = false;
    assert(jit.Prepare(Environment)); // iOS 26: legacy remains false.
    unsigned count = allocations;
    assert(jit.Prepare(Environment) && allocations == count);

    const unsigned char code[] = {0xc7, 0x07, 42, 0, 0, 0, 0xc3};
    {
        CMemoryFunction function(code, sizeof(code));
        assert(function.GetCode() == rx && function.GetWritableCode() == rw);
        assert(std::memcmp(function.GetCode(), code, sizeof(code)) == 0);
        assert(!CMemoryFunction::SetExternalMemory(nullptr, nullptr, 0));
#if defined(__linux__) && defined(__x86_64__)
        unsigned value = 0;
        function(&value);
        assert(value == 42);
#endif
        function.BeginModify();
        static_cast<unsigned char*>(function.GetWritableCode())[2] = 43;
        function.EndModify();
        assert(static_cast<unsigned char*>(function.GetCode())[2] == 43);
        auto clone = function.CreateInstance();
        assert(clone.GetCode() != function.GetCode());
        assert(std::memcmp(clone.GetCode(), function.GetCode(), sizeof(code)) == 0);
        CMemoryFunction moved;
        moved = std::move(clone);
        assert(clone.IsEmpty() && moved.GetWritableCode() != moved.GetCode());
#if defined(__linux__) && defined(__x86_64__)
        moved(&value);
        assert(value == 43);
        puts("Native execution of generated and patched code passed.");
#endif
    }

    // Freed code must be reusable, including adjacent chunks in either order.
    std::vector<std::unique_ptr<CMemoryFunction>> functions;
    for(size_t i = 0; i < page / 16; i++)
        functions.emplace_back(new CMemoryFunction(code, sizeof(code)));
    bool exhausted = false;
    try { CMemoryFunction extra(code, sizeof(code)); }
    catch(const std::bad_alloc&) { exhausted = true; }
    assert(exhausted);
    for(size_t i = 0; i < functions.size(); i += 2) functions[i].reset();
    functions.clear();
    {
        std::vector<unsigned char> bytes(page, 7);
        CMemoryFunction whole(bytes.data(), bytes.size());
        assert(whole.GetCode() == rx);
    }
    std::vector<std::thread> threads;
    for(unsigned i = 0; i < 8; i++)
        threads.emplace_back([&]() {
            for(unsigned j = 0; j < 1000; j++)
            {
                CMemoryFunction function(code, sizeof(code));
                assert(std::memcmp(function.GetCode(), code, sizeof(code)) == 0);
            }
        });
    for(auto& thread : threads) thread.join();
    jit.Release(Environment);
    assert(releases == 2);
    jit.Release(Environment);
    assert(releases == 2);
    assert(jit.Prepare(Environment));
    jit.Release(Environment);
    assert(releases == 3);

    mode = RETRO_EXEC_MEM_MODE_WX_TOGGLE;
    assert(!jit.Prepare(Environment));
    legacy = true;
    assert(jit.Prepare(Environment));
    supported = false;
    assert(jit.Prepare(Environment));
    legacy = false;
    assert(!jit.Prepare(Environment));
    assert(munmap(rx, page) == 0 && munmap(rw, page) == 0);
    fclose(file);
    puts("Play! JIT memory: alias writes, clone/move, reuse, exhaustion, concurrency, retry and cleanup passed.");
}
