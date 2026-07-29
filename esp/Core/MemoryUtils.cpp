#import "MemoryUtils.h"
#include <cerrno>

pid_t GetGameProcesspid(char* GameProcessName) {
    size_t length = 0;
    static const int name[] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    int err = sysctl((int *)name, (sizeof(name) / sizeof(*name)) - 1, NULL, &length, NULL, 0);

    if (err == -1) {
        err = errno;
    }

    if (err == 0) {
        struct kinfo_proc *procBuffer = (struct kinfo_proc *)malloc(length);
        if (procBuffer == NULL) {
            return -1;
        }

        err = sysctl((int *)name, (sizeof(name) / sizeof(*name)) - 1, procBuffer, &length, NULL, 0);
        if (err == -1) {
            err = errno;
            free(procBuffer);
            return -1;
        }

        int count = (int)length / sizeof(struct kinfo_proc);
        for (int i = 0; i < count; ++i) {
            const char *procname = procBuffer[i].kp_proc.p_comm;
            pid_t Processpid = procBuffer[i].kp_proc.p_pid;

            if (strstr(procname, GameProcessName)) {
                free(procBuffer);
                return Processpid;
            }
        }

        free(procBuffer);
    }

    return -1;
}

vm_map_offset_t GetGameModule_Base(char* GameProcessName) {
    vm_address_t vmoffset = 0;
    vm_size_t vmsize = 0;
    uint32_t nesting_depth = 0;
    struct vm_region_submap_info_64 vbr;
    mach_msg_type_number_t vbrcount = 16;

    pid_t pid = GetGameProcesspid(GameProcessName);

    if (pid == -1) {
        const char *fallbackNames[] = {
            "freefirethm",
            "freefireth_ob",
            "FreeFire",
            NULL
        };
        for (int i = 0; fallbackNames[i] != NULL; i++) {
            pid = GetGameProcesspid((char*)fallbackNames[i]);
            if (pid != -1) break;
        }
    }

    if (pid == -1) {
        return 0;
    }

    kern_return_t kret = task_for_pid(mach_task_self(), pid, &get_task);

    if (get_task != MACH_PORT_NULL) {
        kern_return_t kr = vm_region_recurse_64(get_task, &vmoffset, &vmsize, &nesting_depth, (vm_region_recurse_info_t)&vbr, &vbrcount);
        if (kr == KERN_SUCCESS) {
            return (vm_map_offset_t)vmoffset;
        }
    }

    return 0;
}

bool _read(long addr, void *buffer, int len)
{
    if (!isVaildPtr(addr)) return false;
    vm_size_t size = 0;
    kern_return_t error = vm_read_overwrite(get_task, (vm_address_t)addr, len, (vm_address_t)buffer, &size);
    if(error != KERN_SUCCESS || size != len)
    {
        return false;
    }
    return true;
}
