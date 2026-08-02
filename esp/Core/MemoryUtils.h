#ifndef MemoryUtils_h
#define MemoryUtils_h

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <sys/sysctl.h>
#include <sys/types.h>

// FIX: KHÔNG include <mach/mach.h> vì nó pull <mach/mach_vm.h>
// trên iOS SDK 16.5+, gây lỗi #error "mach_vm.h unsupported."
#include <mach/mach_init.h>
#include <mach/vm_region.h>
#include <mach/vm_types.h>
#include <mach/kern_return.h>
#include <mach/message.h>
#include <mach/port.h>

// ============================================================
// FIX: Forward declare system calls bị block bởi mach_vm.h
// ============================================================
#ifdef __cplusplus
extern "C" {
#endif

kern_return_t vm_region_recurse_64(
    vm_map_t target_task,
    vm_address_t *address,
    vm_size_t *size,
    natural_t *nesting_depth,
    vm_region_recurse_info_t info,
    mach_msg_type_number_t *infoCnt
);

kern_return_t vm_read_overwrite(
    vm_map_t target_task,
    vm_address_t address,
    vm_size_t size,
    vm_address_t data,
    vm_size_t *outsize
);

#ifdef __cplusplus
}
#endif

extern uint64_t Module_Base;
extern task_t get_task;

// FIX: Strict pointer validation - alignment + user-space + non-zero upper bits
inline bool isVaildPtr(uint64_t addr) {
    // Must be 8-byte aligned
    if ((addr & 0x7) != 0) return false;
    // iOS user-space: 0x100000000 to 0x000007FFFFFFFFFF (47-bit)
    // Exclude kernel/sign-extended addresses like 0xAA0E00000002
    return (addr > 0x100000000ULL && addr < 0x000007F000000000ULL);
}

pid_t GetGameProcesspid(char* GameProcessName);
uint64_t GetGameModule_Base(char* GameProcessName);
bool _read(uint64_t addr, void *buffer, int len);

template<typename T>
T ReadAddr(uint64_t address) {
    T buffer;
    if (_read(address, &buffer, sizeof(T))) {
        return buffer;
    }
    return T();
}

#endif /* MemoryUtils_h */
