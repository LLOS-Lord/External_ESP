#ifndef MemoryUtils_h
#define MemoryUtils_h

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <mach/mach.h>
#include <sys/sysctl.h>
#include <sys/types.h>

extern uint64_t Moudule_Base;

bool isVaildPtr(uint64_t ptr);
int GetGameProcesspid(const char *name);
int GetGameProcesspid_Auto(void);  // NEW: Tự động thử nhiều tên process
void ListAllProcesses(void);        // NEW: Debug - liệt kê tất cả process
uint64_t GetGameModule_Base(int pid);
uint64_t GetModuleSlide(int pid);
bool _read(uint64_t address, void *buffer, size_t size);

template <typename T>
T ReadAddr(uint64_t address) {
    T buffer;
    if (_read(address, &buffer, sizeof(T))) {
        return buffer;
    }
    return T();
}

#endif /* MemoryUtils_h */
