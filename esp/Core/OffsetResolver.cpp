#include "OffsetResolver.h"
#include "Offsets.h"
#include "MemoryUtils.h"
#include "Offsets.h"
#include "Logger.h"
#include <cstring>
#include <mach/mach.h>
#include <cstring>

ResolvedOffsets g_resolved;

// ==========================================
// HELPERS
// ==========================================

static bool tryReadU64(uint64_t addr, uint64_t* out) {
    return _read(addr, out, 8);
}

static bool tryReadU32(uint64_t addr, uint32_t* out) {
    return _read(addr, out, 4);
}

static bool isValidGameManager(uint64_t gm, uint32_t offMatch, uint32_t offDict, 
                                uint64_t* outMatch, int* outCount) {
    uint64_t match = 0;
    if (!tryReadU64(gm + offMatch, &match) || match == 0 || !isVaildPtr(match)) {
        return false;
    }

    uint64_t dict = 0;
    if (!tryReadU64(gm + offDict, &dict) || dict == 0 || !isVaildPtr(dict)) {
        return false;
    }

    int count = 0;
    if (!tryReadU32(dict + 0x20, (uint32_t*)&count)) {
        return false;
    }
    if (count <= 0 || count > 200) {
        return false;
    }

    uint64_t entries = 0;
    if (!tryReadU64(dict + 0x18, &entries) || entries == 0) {
        return false;
    }

    *outMatch = match;
    *outCount = count;
    return true;
}

static bool isValidMatchGame(uint64_t match, uint32_t offLocal, uint64_t* outLocal) {
    uint64_t local = 0;
    if (!tryReadU64(match + offLocal, &local)) {
        return false;
    }
    // LocalPlayer có thể = 0 khi chưa spawn
    if (local != 0 && !isVaildPtr(local)) {
        return false;
    }
    *outLocal = local;
    return true;
}

// ==========================================
// HARD-CODED FALLBACK
// ==========================================

bool tryHardcodedOffsets(uint64_t moduleBase) {
    if (moduleBase == 0) return false;

    uint64_t initBase = moduleBase + OFFSET_InitBase;
    uint64_t ptr = 0;
    if (!tryReadU64(initBase, &ptr) || ptr == 0 || !isVaildPtr(ptr)) {
        return false;
    }

    uint64_t gm = 0;
    if (!tryReadU64(ptr + OFFSET_StaticClass, &gm) || gm == 0 || !isVaildPtr(gm)) {
        return false;
    }

    uint64_t match = 0;
    if (!tryReadU64(gm + OFFSET_CurrentMatch, &match) || match == 0) {
        return false;
    }

    // Xác nhận thêm bằng cách đọc LocalPlayer
    uint64_t local = 0;
    if (!tryReadU64(match + OFFSET_LocalPlayer, &local)) {
        return false;
    }

    ESPLog("[RESOLVE] Hardcoded offsets verified OK");
    g_resolved.off_GM_To_MatchGame = OFFSET_CurrentMatch;
    g_resolved.off_Match_To_LocalPlayer = OFFSET_LocalPlayer;
    g_resolved.off_GM_To_Dict = OFFSET_DictionaryEntities;
    g_resolved.resolved = true;
    return true;
}

// ==========================================
// HEURISTIC SCAN
// ==========================================

bool resolveOffsetsHeuristic(uint64_t moduleBase, uint64_t moduleSize) {
    ESPLog("[RESOLVE] Starting HEURISTIC offset scan...");

    if (get_task == MACH_PORT_NULL) {
        ESPLog("[RESOLVE] No task port!");
        return false;
    }

    // FIX: vm_region_recurse_64 cần vm_address_t* (unsigned long*), không phải mach_vm_address_t*
    vm_address_t address = 0;
    vm_size_t size = 0;
    natural_t depth = 0;
    struct vm_region_submap_info_64 vbr;
    mach_msg_type_number_t vbrcount = VM_REGION_SUBMAP_INFO_COUNT_64;

    int regionsScanned = 0;
    int candidatesTested = 0;

    // Offset candidate ranges (tuned for Il2Cpp/Unity games)
    const uint32_t MATCH_OFFS[] = {0x30, 0x38, 0x40, 0x48, 0x50, 0x58, 0x60, 0x68, 0x70, 0x78, 0x80};
    const int MATCH_COUNT = sizeof(MATCH_OFFS) / sizeof(MATCH_OFFS[0]);

    const uint32_t LOCAL_OFFS[] = {0x20, 0x28, 0x30, 0x38, 0x40, 0x48, 0x50, 0x58};
    const int LOCAL_COUNT = sizeof(LOCAL_OFFS) / sizeof(LOCAL_OFFS[0]);

    const uint32_t DICT_OFFS[] = {0x30, 0x38, 0x40, 0x48, 0x50, 0x58, 0x60, 0x68, 0x70, 0x78, 0x80};
    const int DICT_COUNT = sizeof(DICT_OFFS) / sizeof(DICT_OFFS[0]);

    while (vm_region_recurse_64(get_task, &address, &size, &depth, 
           (vm_region_recurse_info_t)&vbr, &vbrcount) == KERN_SUCCESS) {

        // Chỉ quét vùng heap/data: RW- hoặc R-- (một số vùng data chỉ read)
        bool isRW = (vbr.protection & VM_PROT_READ) && (vbr.protection & VM_PROT_WRITE);
        bool isRO = (vbr.protection & VM_PROT_READ) && !(vbr.protection & VM_PROT_WRITE);

        if (!isRW && !isRO) {
            address += size;
            continue;
        }

        // Bỏ qua vùng quá nhỏ hoặc quá lớn
        if (size < 1024 * 1024 || size > 512 * 1024 * 1024) {
            address += size;
            continue;
        }

        // Bỏ qua vùng module image (đã biết base)
        if (address >= moduleBase && address < moduleBase + moduleSize) {
            address += size;
            continue;
        }

        regionsScanned++;
        ESPLog("[RESOLVE] Scanning region 0x%llX - 0x%llX (size=%zuMB, prot=%d)", 
               (uint64_t)address, (uint64_t)(address + size), 
               (size_t)(size / (1024*1024)), vbr.protection);

        size_t chunkSize = 4 * 1024 * 1024; // 4MB chunks
        for (size_t offset = 0; offset < size; offset += chunkSize) {
            size_t currentSize = (size - offset < chunkSize) ? (size - offset) : chunkSize;
            uint8_t* buffer = (uint8_t*)malloc(currentSize);
            if (!buffer) continue;

            vm_size_t readSize = 0;
            kern_return_t kr = vm_read_overwrite(get_task, (mach_vm_address_t)(address + offset), currentSize, 
                                                   (vm_address_t)buffer, &readSize);
            if (kr != KERN_SUCCESS || readSize != currentSize) {
                free(buffer);
                continue;
            }

            // Scan từng 8-byte aligned pointer
            for (size_t i = 0; i + 8 <= currentSize; i += 8) {
                uint64_t candidate = 0;
                memcpy(&candidate, buffer + i, 8);
                if (candidate == 0 || !isVaildPtr(candidate)) continue;

                // Nhanh: thử offset phổ biến nhất trước (0x50 match, 0x30 local, 0x40 dict)
                uint64_t match = 0;
                int count = 0;
                uint64_t local = 0;

                bool quickFound = false;
                for (int mi = 0; mi < MATCH_COUNT && !quickFound; mi++) {
                    if (!isValidGameManager(candidate, MATCH_OFFS[mi], 0x40, &match, &count)) continue;
                    if (!isValidMatchGame(match, 0x30, &local)) continue;

                    // Quick validate: thử đọc 1 player từ list
                    uint64_t dict = 0;
                    if (!tryReadU64(candidate + 0x40, &dict)) continue;
                    uint64_t entries = 0;
                    if (!tryReadU64(dict + 0x18, &entries) || entries == 0) continue;

                    uint64_t firstPlayer = 0;
                    if (!tryReadU64(entries, &firstPlayer) || firstPlayer == 0) continue;

                    // Kiểm tra HP hoặc Team hợp lý
                    uint32_t hp = 0, team = 0;
                    bool hasValidStats = false;
                    if (tryReadU32(firstPlayer + OFFSET_CurHP, &hp) && hp > 0 && hp <= 200) {
                        hasValidStats = true;
                    }
                    if (!hasValidStats && tryReadU32(firstPlayer + OFFSET_TeamID, &team) && team < 50) {
                        hasValidStats = true;
                    }

                    if (hasValidStats || count >= 1) {
                        g_resolved.off_GM_To_MatchGame = MATCH_OFFS[mi];
                        g_resolved.off_Match_To_LocalPlayer = 0x30;
                        g_resolved.off_GM_To_Dict = 0x40;
                        g_resolved.gameManagerInstance = candidate;
                        g_resolved.hasInstance = true;
                        g_resolved.resolved = true;

                        ESPLog("[RESOLVE] QUICK FOUND! GM=0x%llX", candidate);
                        ESPLog("[RESOLVE]   GM->Match: 0x%X", MATCH_OFFS[mi]);
                        ESPLog("[RESOLVE]   Match->Local: 0x30");
                        ESPLog("[RESOLVE]   GM->Dict: 0x40");
                        ESPLog("[RESOLVE]   Player count: %d", count);

                        free(buffer);
                        return true;
                    }
                }

                // Nếu quick fail, thử brute-force đầy đủ (chỉ test 500 candidates đầu)
                if (candidatesTested > 500) {
                    free(buffer);
                    buffer = NULL;
                    break;
                }
                candidatesTested++;

                for (int mi = 0; mi < MATCH_COUNT; mi++) {
                    uint64_t match2 = 0;
                    int count2 = 0;
                    if (!isValidGameManager(candidate, MATCH_OFFS[mi], 0x40, &match2, &count2)) continue;

                    for (int li = 0; li < LOCAL_COUNT; li++) {
                        uint64_t local2 = 0;
                        if (!isValidMatchGame(match2, LOCAL_OFFS[li], &local2)) continue;

                        for (int di = 0; di < DICT_COUNT; di++) {
                            uint64_t dict2 = 0;
                            if (!tryReadU64(candidate + DICT_OFFS[di], &dict2)) continue;
                            uint64_t entries2 = 0;
                            if (!tryReadU64(dict2 + 0x18, &entries2) || entries2 == 0) continue;
                            int count3 = 0;
                            if (!tryReadU32(dict2 + 0x20, (uint32_t*)&count3) || count3 <= 0) continue;

                            // Validate player
                            uint64_t firstPlayer = 0;
                            if (!tryReadU64(entries2, &firstPlayer) || firstPlayer == 0) continue;

                            uint32_t hp = 0;
                            if (tryReadU32(firstPlayer + OFFSET_CurHP, &hp) && hp > 0 && hp <= 200) {
                                // FOUND!
                                g_resolved.off_GM_To_MatchGame = MATCH_OFFS[mi];
                                g_resolved.off_Match_To_LocalPlayer = LOCAL_OFFS[li];
                                g_resolved.off_GM_To_Dict = DICT_OFFS[di];
                                g_resolved.gameManagerInstance = candidate;
                                g_resolved.hasInstance = true;
                                g_resolved.resolved = true;

                                ESPLog("[RESOLVE] BRUTE FOUND! GM=0x%llX", candidate);
                                ESPLog("[RESOLVE]   GM->Match: 0x%X", MATCH_OFFS[mi]);
                                ESPLog("[RESOLVE]   Match->Local: 0x%X", LOCAL_OFFS[li]);
                                ESPLog("[RESOLVE]   GM->Dict: 0x%X", DICT_OFFS[di]);
                                ESPLog("[RESOLVE]   Players: %d, HP=%d", count3, hp);

                                free(buffer);
                                return true;
                            }
                        }
                    }
                }
            }

            if (buffer) free(buffer);
        }

        address += size;
    }

    ESPLog("[RESOLVE] Heuristic FAILED. Scanned %d regions, %d candidates.", 
           regionsScanned, candidatesTested);
    return false;
}

// ==========================================
// MAIN ENTRY
// ==========================================

bool resolveOffsets(uint64_t moduleBase, uint64_t moduleSize) {
    if (g_resolved.resolved) return true;

    ESPLog("[RESOLVE] Attempting offset resolution...");

    // 1. Thử hardcoded
    if (tryHardcodedOffsets(moduleBase)) {
        ESPLog("[RESOLVE] Using HARDCODED offsets");
        logResolvedOffsets();
        return true;
    }

    // 2. Thử heuristic scan
    if (resolveOffsetsHeuristic(moduleBase, moduleSize)) {
        ESPLog("[RESOLVE] Using HEURISTIC offsets");
        logResolvedOffsets();
        return true;
    }

    ESPLog("[RESOLVE] ALL methods failed");
    return false;
}

void logResolvedOffsets() {
    ESPLog("[RESOLVE] ===== RESOLVED OFFSETS =====");
    ESPLog("[RESOLVE] GM->MatchGame:  0x%X", g_resolved.off_GM_To_MatchGame);
    ESPLog("[RESOLVE] Match->Local:   0x%X", g_resolved.off_Match_To_LocalPlayer);
    ESPLog("[RESOLVE] GM->Dict:       0x%X", g_resolved.off_GM_To_Dict);
    ESPLog("[RESOLVE] GM Instance:    0x%llX", g_resolved.gameManagerInstance);
    ESPLog("[RESOLVE] ==============================");
}
