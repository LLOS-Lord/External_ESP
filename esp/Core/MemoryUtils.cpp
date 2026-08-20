#import "MemoryUtils.h"
// FIX: Thêm header cho sysctl, kinfo_proc
#include <sys/sysctl.h>
#include <cerrno>
#include "Logger.h"

task_t get_task = MACH_PORT_NULL;
uint64_t Module_Base = 0;

pid_t GetGameProcesspid(const char* GameProcessName) {
    size_t length = 0;
    static const int name[] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    int err = sysctl((int *)name, (sizeof(name) / sizeof(*name)) - 1, NULL, &length, NULL, 0);
    if (err == -1) {
        ESPLog("[PROC] sysctl first call failed, errno=%d", errno);
        return -1;
    }

    struct kinfo_proc *procBuffer = (struct kinfo_proc *)malloc(length);
    if (procBuffer == NULL) {
        ESPLog("[PROC] malloc failed");
        return -1;
    }

    err = sysctl((int *)name, (sizeof(name) / sizeof(*name)) - 1, procBuffer, &length, NULL, 0);
    if (err == -1) {
        ESPLog("[PROC] sysctl second call failed, errno=%d", errno);
        free(procBuffer);
        return -1;
    }

    int count = (int)length / sizeof(struct kinfo_proc);
    ESPLog("[PROC] Total processes found: %d", count);

    pid_t bestMatch = -1;

    for (int i = 0; i < count; ++i) {
        const char *procname = procBuffer[i].kp_proc.p_comm;
        pid_t Processpid = procBuffer[i].kp_proc.p_pid;

        if (strcmp(procname, GameProcessName) == 0 || strstr(procname, GameProcessName)) {
            ESPLog("[PROC] MATCH '%s' -> pid=%d", procname, Processpid);
            bestMatch = Processpid;
            break;
        }
    }

    if (bestMatch == -1) {
        ESPLog("[PROC] '%s' not found directly. Scanning all processes for Free Fire...", GameProcessName);
        for (int i = 0; i < count; ++i) {
            const char *procname = procBuffer[i].kp_proc.p_comm;
            pid_t Processpid = procBuffer[i].kp_proc.p_pid;

            if (strstr(procname, "Free") || strstr(procname, "Fire") || 
                strstr(procname, "free") || strstr(procname, "fire") ||
                strstr(procname, "Garena") || strstr(procname, "garena")) {
                ESPLog("[PROC] CANDIDATE: '%s' pid=%d", procname, Processpid);
            }

            if (strstr(procname, "Free Fire") || strstr(procname, "freefire") || 
                strstr(procname, "FreeFire") || strstr(procname, "GarenaFreeFire") ||
                strstr(procname, "freefireth") || strstr(procname, "freefirethm") ||
                strstr(procname, "freefireth_ob")) {
                ESPLog("[PROC] FOUND Free Fire process: '%s' pid=%d", procname, Processpid);
                bestMatch = Processpid;
                break;
            }
        }
    }

    if (bestMatch == -1) {
        for (int i = 0; i < count; ++i) {
            const char *procname = procBuffer[i].kp_proc.p_comm;
            pid_t Processpid = procBuffer[i].kp_proc.p_pid;
            if (strstr(procname, "Fire") || strstr(procname, "fire")) {
                ESPLog("[PROC] FALLBACK MATCH (contains Fire): '%s' pid=%d", procname, Processpid);
                bestMatch = Processpid;
                break;
            }
        }
    }

    free(procBuffer);

    if (bestMatch == -1) {
        ESPLog("[PROC] FAILED: No matching process found for '%s'", GameProcessName);
    } else {
        ESPLog("[PROC] SUCCESS: Selected pid=%d", bestMatch);
    }

    return bestMatch;
}

uint64_t GetGameModule_Base(const char* GameProcessName) {
    vm_address_t vmoffset = 0;
    vm_size_t vmsize = 0;
    uint32_t nesting_depth = 0;
    struct vm_region_submap_info_64 vbr;
    mach_msg_type_number_t vbrcount = VM_REGION_SUBMAP_INFO_COUNT_64;

    ESPLog("[PROC] Looking for process: '%s'", GameProcessName);
    pid_t pid = GetGameProcesspid(GameProcessName);

    if (pid == -1) {
        ESPLog("[PROC] Could not find any process, aborting");
        return 0;
    }

    ESPLog("[PROC] Attaching to pid=%d...", pid);
    kern_return_t kret = task_for_pid(mach_task_self(), pid, &get_task);

    if (kret != KERN_SUCCESS) {
        ESPLog("[PROC] task_for_pid FAILED: %d", kret);
        return 0;
    }

    ESPLog("[PROC] task_for_pid SUCCESS, task port=%u", get_task);

    if (get_task != MACH_PORT_NULL) {
        kern_return_t kr = vm_region_recurse_64(get_task, &vmoffset, &vmsize, &nesting_depth, (vm_region_recurse_info_t)&vbr, &vbrcount);
        if (kr == KERN_SUCCESS) {
            ESPLog("[PROC] Module Base = 0x%llX", (uint64_t)vmoffset);
            return (uint64_t)vmoffset;
        } else {
            ESPLog("[PROC] vm_region_recurse_64 FAILED: %d", kr);
        }
    }

    return 0;
}