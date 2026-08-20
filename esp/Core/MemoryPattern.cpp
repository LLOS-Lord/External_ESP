#include "MemoryPattern.h"
#include "MemoryUtils.h"
#include "Logger.h"
#include <cstring>
#include <cstdlib>
#include <mach/mach.h>

// ==========================================
// PATTERN PARSER
// ==========================================

static bool parsePattern(const char* pattern, unsigned char* bytes, unsigned char* mask, int* outLen) {
    int len = 0;
    while (*pattern) {
        if (*pattern == ' ' || *pattern == '\t') { pattern++; continue; }
        if (*pattern == '?') {
            bytes[len] = 0x00;
            mask[len] = 0x00;
            len++;
            pattern++;
            if (*pattern == '?') pattern++;
            continue;
        }
        if (pattern[0] && pattern[1]) {
            unsigned int byte = 0;
            if (sscanf(pattern, "%2x", &byte) == 1) {
                bytes[len] = (unsigned char)byte;
                mask[len] = 0xFF;
                len++;
                pattern += 2;
                continue;
            }
        }
        return false;
    }
    *outLen = len;
    return len > 0;
}

// ==========================================
// PATTERN SCAN (with chunk overlap fix)
// ==========================================

uint64_t patternScan(uint64_t start, size_t size, const char* pattern) {
    if (get_task == MACH_PORT_NULL || start == 0 || size == 0) return 0;

    unsigned char bytes[256];
    unsigned char mask[256];
    int patLen = 0;
    if (!parsePattern(pattern, bytes, mask, &patLen) || patLen == 0) {
        ESPLog("[PAT] Invalid pattern");
        return 0;
    }

    ESPLog("[PAT] Scanning 0x%llX - 0x%llX, patLen=%d", start, start + size, patLen);

    size_t chunkSize = 4 * 1024 * 1024; // 4MB
    size_t overlap = (patLen > 1) ? (patLen - 1) : 0;
    uint8_t* buffer = (uint8_t*)malloc(chunkSize + overlap);
    if (!buffer) return 0;

    size_t prevOverlap = 0;
    uint64_t found = 0;

    for (size_t offset = 0; offset < size && found == 0; offset += (chunkSize - overlap)) {
        size_t currentSize = (size - offset < chunkSize) ? (size - offset) : chunkSize;

        // Copy overlap từ chunk trước vào đầu buffer
        if (prevOverlap > 0) {
            memmove(buffer, buffer + chunkSize, prevOverlap);
        }

        vm_size_t readSize = 0;
        kern_return_t kr = vm_read_overwrite(get_task, start + offset, currentSize, 
                                               (vm_address_t)(buffer + prevOverlap), &readSize);
        if (kr != KERN_SUCCESS || readSize != currentSize) {
            prevOverlap = 0;
            continue;
        }

        size_t searchLen = prevOverlap + currentSize;
        for (size_t i = 0; i + patLen <= searchLen && found == 0; i++) {
            bool match = true;
            for (int j = 0; j < patLen; j++) {
                if (mask[j] != 0x00 && buffer[i + j] != bytes[j]) {
                    match = false;
                    break;
                }
            }
            if (match) {
                found = start + offset + i - prevOverlap;
            }
        }

        prevOverlap = (currentSize >= overlap) ? overlap : currentSize;
    }

    free(buffer);
    if (found != 0) ESPLog("[PAT] Found at 0x%llX", found);
    else ESPLog("[PAT] Not found");
    return found;
}

uint64_t patternScanFirst(uint64_t start, size_t size, const char* pattern) {
    return patternScan(start, size, pattern);
}

// ==========================================
// INIT BASE RESOLVE
// ==========================================

uint64_t autoResolveInitBase(uint64_t moduleBase, uint64_t moduleSize) {
    if (moduleBase == 0) return 0;

    // Pattern: LDR X0, [X0, #0x...] hoặc ADRP + ADD + LDR
    // Đây là pattern đại diện, có thể cần tune cho từng version
    const char* p1 = "00 00 00 58 ?? ?? ?? ?? ?? ?? ?? ?? 00 00 40 F9";
    uint64_t r1 = patternScan(moduleBase, moduleSize, p1);
    if (r1 != 0) {
        ESPLog("[PAT] InitBase pattern1 at 0x%llX", r1);
        return r1;
    }

    const char* p2 = "?? ?? ?? 90 ?? ?? ?? ?? ?? ?? ?? 91 ?? ?? ?? F9";
    uint64_t r2 = patternScan(moduleBase, moduleSize, p2);
    if (r2 != 0) {
        ESPLog("[PAT] InitBase pattern2 at 0x%llX", r2);
        return r2;
    }

    return 0;
}

// ==========================================
// GAME MANAGER RESOLVE (brute-force fallback)
// ==========================================

uint64_t autoResolveGameManager(uint64_t moduleBase, uint64_t moduleSize) {
    if (get_task == MACH_PORT_NULL) return 0;

    ESPLog("[PAT] Brute-force scanning for GameManager...");

    // FIX: vm_region_recurse_64 cần vm_address_t* (unsigned long*), không phải mach_vm_address_t*
    vm_address_t address = 0;
    vm_size_t size = 0;
    natural_t depth = 0;
    struct vm_region_submap_info_64 vbr;
    mach_msg_type_number_t vbrcount = VM_REGION_SUBMAP_INFO_COUNT_64;

    while (vm_region_recurse_64(get_task, &address, &size, &depth, 
           (vm_region_recurse_info_t)&vbr, &vbrcount) == KERN_SUCCESS) {

        if ((vbr.protection & VM_PROT_READ) == 0 || size > 512*1024*1024) {
            address += size;
            continue;
        }

        size_t chunkSize = 4 * 1024 * 1024;
        for (size_t offset = 0; offset < size; offset += chunkSize) {
            size_t currentSize = (size - offset < chunkSize) ? (size - offset) : chunkSize;
            uint8_t* buffer = (uint8_t*)malloc(currentSize);
            if (!buffer) continue;

            vm_size_t readSize = 0;
            if (vm_read_overwrite(get_task, (mach_vm_address_t)(address + offset), currentSize, 
                                  (vm_address_t)buffer, &readSize) == KERN_SUCCESS) {

                for (size_t i = 0; i + 8 <= currentSize; i += 8) {
                    // Đọc giá trị pointer (instance address)
                    uint64_t candidate = 0;
                    memcpy(&candidate, buffer + i, 8);
                    if (candidate == 0 || !isVaildPtr(candidate)) continue;

                    // Thử đọc MatchGame tại offset 0x50 (phổ biến nhất)
                    uint64_t match = 0;
                    if (!_read(candidate + 0x50, &match, 8) || match == 0 || !isVaildPtr(match)) continue;

                    // Thử đọc LocalPlayer tại offset 0x30
                    uint64_t lp = 0;
                    if (!_read(match + 0x30, &lp, 8)) continue;
                    if (lp != 0 && !isVaildPtr(lp)) continue;

                    // Thử đọc Dictionary tại offset 0x40
                    uint64_t dict = 0;
                    if (!_read(candidate + 0x40, &dict, 8) || dict == 0 || !isVaildPtr(dict)) continue;

                    uint64_t entries = 0;
                    if (!_read(dict + 0x18, &entries, 8) || entries == 0) continue;

                    int count = 0;
                    if (!_read(dict + 0x20, &count, 4)) continue;
                    if (count > 0 && count <= 100) {
                        ESPLog("[PAT] GameManager found: 0x%llX, match=0x%llX, players=%d", 
                               candidate, match, count);
                        free(buffer);
                        return candidate;
                    }
                }
            }
            free(buffer);
        }
        address += size;
    }

    ESPLog("[PAT] Brute-force failed");
    return 0;
}
