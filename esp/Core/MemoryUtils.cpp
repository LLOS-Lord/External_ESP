#import "MemoryUtils.h"
#import "Logger.h"

pid_t GetGameProcesspid(char* GameProcessName) {
    size_t length = 0;
    static const int name[] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    int err = sysctl((int *)name, (sizeof(name) / sizeof(*name)) - 1, NULL, &length, NULL, 0);

    if (err == -1) {
        err = errno;
    }

    ESPLog("[MEM] sysctl length=%zu err=%d", length, err);

    if (err == 0) {
        struct kinfo_proc *procBuffer = (struct kinfo_proc *)malloc(length);
        if (procBuffer == NULL) {
            ESPLog("[MEM] malloc failed");
            return -1;
        }

        err = sysctl((int *)name, (sizeof(name) / sizeof(*name)) - 1, procBuffer, &length, NULL, 0);
        if (err == -1) {
            err = errno;
            free(procBuffer);
            ESPLog("[MEM] sysctl second call failed err=%d", err);
            return -1;
        }

        int count = (int)length / sizeof(struct kinfo_proc);
        ESPLog("[MEM] Total processes: %d", count);

        for (int i = 0; i < count; ++i) {
            const char *procname = procBuffer[i].kp_proc.p_comm;
            pid_t Processpid = procBuffer[i].kp_proc.p_pid;

            if (strstr(procname, GameProcessName)) {
                ESPLog("[MEM] FOUND process '%s' pid=%d", procname, Processpid);
                free(procBuffer);
                return Processpid;
            }
        }

        ESPLog("[MEM] Process '%s' NOT FOUND", GameProcessName);
        free(procBuffer);
    }

    return -1;
}

vm_map_offset_t GetGameModule_Base(char* GameProcessName) {
    vm_map_offset_t vmoffset = 0;
    vm_map_size_t vmsize = 0;
    uint32_t nesting_depth = 0;
    struct vm_region_submap_info_64 vbr;
    mach_msg_type_number_t vbrcount = 16;

    pid_t pid = GetGameProcesspid(GameProcessName);
    if (pid == -1) {
        ESPLog("[MEM] GetGameModule_Base: pid=-1");
        return 0;
    }

    ESPLog("[MEM] Getting task for pid=%d", pid);
    kern_return_t kret = task_for_pid(mach_task_self(), pid, &get_task);
    ESPLog("[MEM] task_for_pid result=%d task=%u", kret, get_task);

    if (get_task != MACH_PORT_NULL) {
        kern_return_t kr = mach_vm_region_recurse(get_task, &vmoffset, &vmsize, &nesting_depth, (vm_region_recurse_info_t)&vbr, &vbrcount);
        ESPLog("[MEM] mach_vm_region_recurse result=%d vmoffset=0x%llX vmsize=0x%llX", kr, vmoffset, vmsize);
        if (kr == KERN_SUCCESS) {
            ESPLog("[MEM] Module Base = 0x%llX", vmoffset);
            return vmoffset;
        }
    }

    ESPLog("[MEM] GetGameModule_Base FAILED");
    return 0;
}

bool _read(long addr, void *buffer, int len)
{
    if (!isVaildPtr(addr)) {
        ESPLog("[MEM] _read INVALID addr=0x%lX", addr);
        return false;
    }
    vm_size_t size = 0;
    kern_return_t error = vm_read_overwrite(get_task, (vm_address_t)addr, len, (vm_address_t)buffer, &size);
    if(error != KERN_SUCCESS || size != len)
    {
        ESPLog("[MEM] _read FAILED addr=0x%lX len=%d err=%d size=%zu", addr, len, error, size);
        return false;
    }
    return true;
}
