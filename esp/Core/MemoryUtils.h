#ifndef MemoryUtils_h
#define MemoryUtils_h

#include <mach/mach.h>
#include <cstdint>
#include <string>
#include <vector>

extern mach_port_t get_task;
extern uint64_t Module_Base;

// ==========================================
// POINTER VALIDATION
// ==========================================

inline bool isVaildPtr(uint64_t addr) {
    if (addr == 0) return false;
    // Chấp nhận 4-byte hoặc 8-byte aligned (Il2Cpp có thể dùng 4-byte)
    if ((addr & 0x3) != 0) return false;
    // iOS user-space range (nới rộng cho PAC pointers)
    return (addr >= 0x100000000ULL && addr < 0x800000000000ULL);
}

// ==========================================
// MEMORY READ
// ==========================================

inline bool _read(uint64_t address, void* buffer, size_t len) {
    if (get_task == MACH_PORT_NULL || address == 0 || buffer == nullptr || len == 0)
        return false;
    vm_size_t size = 0;
    kern_return_t kr = vm_read_overwrite(get_task, address, len, (vm_address_t)buffer, &size);
    return (kr == KERN_SUCCESS && size == len);
}

template <typename T>
inline T ReadAddr(uint64_t address) {
    T buffer{};
    _read(address, &buffer, sizeof(T));
    return buffer;
}

inline int readU32(uint64_t address) {
    return ReadAddr<int>(address);
}

inline float readFloat(uint64_t address) {
    return ReadAddr<float>(address);
}

inline uint64_t readU64(uint64_t address) {
    return ReadAddr<uint64_t>(address);
}

// ==========================================
// PROCESS / MODULE
// ==========================================

uint64_t GetGameModule_Base(const char* moduleName);

#endif /* MemoryUtils_h */
