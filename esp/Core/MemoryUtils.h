#ifndef MemoryUtils_h
#define MemoryUtils_h

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <mach/mach.h>
#include <sys/sysctl.h>
#include <sys/types.h>

extern vm_map_offset_t Moudule_Base;
extern task_t get_task;

inline bool isVaildPtr(long addr) {
    return (addr > 0x100000000 && addr < 0xFFFFFFFFFFFF);
}

pid_t GetGameProcesspid(char* GameProcessName);
vm_map_offset_t GetGameModule_Base(char* GameProcessName);
bool _read(long addr, void *buffer, int len);

template<typename T>
T ReadAddr(long address) {
    T buffer;
    if (_read(address, &buffer, sizeof(T))) {
        return buffer;
    }
    return T();
}

#endif /* MemoryUtils_h */
