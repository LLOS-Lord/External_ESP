#include "MemoryUtils.h"

uint64_t Moudule_Base = 0;

bool isVaildPtr(uint64_t ptr) {
    return (ptr > 0x100000000 && ptr < 0xFFFFFFFFFFFF);
}

int GetGameProcesspid(const char *name) {
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t size;

    if (sysctl(mib, 4, NULL, &size, NULL, 0) < 0) {
        return -1;
    }

    struct kinfo_proc *process = NULL;
    struct kinfo_proc *newprocess = NULL;

    do {
        size += size / 10;
        newprocess = (struct kinfo_proc *)realloc(process, size);
        if (!newprocess) {
            if (process) free(process);
            return -1;
        }
        process = newprocess;
        if (sysctl(mib, 4, process, &size, NULL, 0) < 0) {
            free(process);
            return -1;
        }
    } while (size % sizeof(struct kinfo_proc) != 0);

    int count = (int)(size / sizeof(struct kinfo_proc));
    int pid = -1;

    for (int i = 0; i < count; i++) {
        if (strcmp(process[i].kp_proc.p_comm, name) == 0) {
            pid = process[i].kp_proc.p_pid;
            break;
        }
    }

    free(process);
    return pid;
}

// FIX: Thử nhiều tên process phổ biến của Free Fire
int GetGameProcesspid_Auto() {
    const char *processNames[] = {
        "freefireth",
        "freefirethm",
        "freefireth_ob",
        "com.dts.freefireth",
        "com.dts.freefirethm",
        "FreeFire",
        "FreeFireTh",
        NULL
    };

    for (int i = 0; processNames[i] != NULL; i++) {
        int pid = GetGameProcesspid(processNames[i]);
        if (pid > 0) {
            NSLog(@"[MEM] Found process '%s' with pid=%d", processNames[i], pid);
            return pid;
        }
    }

    // Nếu không tìm thấy, liệt kê tất cả process để debug
    NSLog(@"[MEM] WARNING: No Free Fire process found. Listing all processes:");
    ListAllProcesses();

    return -1;
}

// Hàm debug: Liệt kê tất cả process
void ListAllProcesses() {
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t size;

    if (sysctl(mib, 4, NULL, &size, NULL, 0) < 0) return;

    struct kinfo_proc *process = (struct kinfo_proc *)malloc(size);
    if (!process) return;

    if (sysctl(mib, 4, process, &size, NULL, 0) < 0) {
        free(process);
        return;
    }

    int count = (int)(size / sizeof(struct kinfo_proc));
    for (int i = 0; i < count; i++) {
        NSLog(@"[MEM] Process[%d]: name=%s pid=%d", i, process[i].kp_proc.p_comm, process[i].kp_proc.p_pid);
    }

    free(process);
}

uint64_t GetGameModule_Base(int pid) {
    if (pid < 0) {
        NSLog(@"[MEM] GetGameModule_Base: pid=%d INVALID", pid);
        return 0;
    }

    task_t task;
    kern_return_t kr = task_for_pid(mach_task_self(), pid, &task);
    if (kr != KERN_SUCCESS) {
        NSLog(@"[MEM] task_for_pid failed: %s", mach_error_string(kr));
        return 0;
    }

    vm_address_t address = 0;
    vm_size_t size = 0;
    uint32_t depth = 1;

    while (1) {
        struct vm_region_submap_info_64 info;
        mach_msg_type_number_t count = VM_REGION_SUBMAP_INFO_COUNT_64;

        kr = vm_region_recurse_64(task, &address, &size, &depth, (vm_region_info_64_t)&info, &count);
        if (kr != KERN_SUCCESS) break;

        if (info.protection & VM_PROT_EXECUTE) {
            // Found executable region - likely the main module
            // Tìm base address thực sự bằng cách đọc header
            uint64_t base = address;

            // Kiểm tra Mach-O header
            uint32_t magic = 0;
            vm_size_t read_size = 0;
            vm_read_overwrite(task, address, sizeof(uint32_t), (vm_address_t)&magic, &read_size);

            if (magic == MH_MAGIC_64 || magic == MH_CIGAM_64 || magic == FAT_MAGIC || magic == FAT_CIGAM) {
                NSLog(@"[MEM] Found module base: 0x%llX", base);
                return base;
            }
        }

        address += size;
    }

    NSLog(@"[MEM] Could not find module base");
    return 0;
}

uint64_t GetModuleSlide(int pid) {
    // Tính slide từ base address
    // Thường dùng khi ASLR được bật
    uint64_t base = GetGameModule_Base(pid);
    if (base == 0) return 0;

    // Đọc MH header để tìm preferred load address
    // Slide = Base - PreferredAddress
    // Đơn giản hóa: trả về base (coi như slide = base nếu preferred = 0)
    return base;
}

bool _read(uint64_t address, void *buffer, size_t size) {
    if (!isVaildPtr(address)) {
        // NSLog(@"[MEM] _read INVALID addr=0x%llX", address);
        return false;
    }

    vm_size_t read_size = 0;
    kern_return_t kr = vm_read_overwrite(mach_task_self(), address, size, (vm_address_t)buffer, &read_size);

    if (kr != KERN_SUCCESS || read_size != size) {
        // NSLog(@"[MEM] _read FAILED addr=0x%llX kr=%d", address, kr);
        return false;
    }

    return true;
}
