#pragma once
#include <cstdint>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <mach/vm_map.h>
#include <mach-o/dyld_images.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <mach/mach_traps.h>
#include <mach/mach_init.h>
#include <mach/mach_port.h>
#include <mach/vm_region.h>
#include <mach/vm_prot.h>
#include <mach/task_info.h>
#include <mach/task.h>
#include <sys/sysctl.h>
#include <dlfcn.h>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

extern task_t g_targetTask;
extern uint64_t g_moduleBase;

bool GetProcessByName(const char* procName);
bool AttachToProcess(pid_t pid);
uint64_t GetGameModule_Base(char* moduleName);

// ============================================================
// Memory read helpers
// ============================================================
inline bool _read(uint64_t address, void* buffer, size_t size) {
    if (address == 0 || g_targetTask == MACH_PORT_NULL) return false;
    vm_size_t sz = size;
    kern_return_t kr = vm_read_overwrite(g_targetTask, (vm_address_t)address, (vm_size_t)size, (vm_address_t)buffer, &sz);
    return (kr == KERN_SUCCESS && sz == size);
}

template <typename T>
inline T ReadAddr(uint64_t address) {
    T val = 0;
    _read(address, &val, sizeof(T));
    return val;
}

// ============================================================
// Tightened pointer validation
// - Must be non-zero
// - Must be 8-byte aligned (all Unity/Il2Cpp objects are)
// - Must be in user-space range (below kernel boundary)
// - Must be above minimum module base
// ============================================================
inline bool isVaildPtr(uint64_t addr) {
    return addr != 0
        && (addr & 0x7) == 0          // 8-byte aligned
        && addr > 0x100000000         // above typical module base
        && addr < 0x800000000000;     // below ARM64 kernel/user boundary (bit 47 = 0)
}
