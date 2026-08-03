#import "GameLogic.h"
#include "Logger.h"
#include "Offsets.h"
#include <cstring>

NSString* ReadIl2CppString(uint64_t strAddr) {
    if (!isVaildPtr(strAddr)) return @"???";
    int32_t len = 0;
    if (!_read(strAddr + 0x10, &len, 4)) return @"???";
    if (len <= 0 || len > 256) return @"???";
    uint16_t buffer[256];
    if (!_read(strAddr + 0x14, buffer, len * 2)) return @"???";
    buffer[len] = 0;
    return [[NSString alloc] initWithBytes:buffer length:len*2 encoding:NSUTF16LittleEndianStringEncoding];
}

// ============================================================
// STRICT Match validator - dùng _read trực tiếp
// ============================================================
bool isValidMatch(uint64_t match) {
    if (!isVaildPtr(match)) return false;

    uint64_t lp = 0;
    bool lpOk = _read(match + OFFSET_LocalPlayer, &lp, 8);

    uint32_t status = 0;
    bool statusOk = _read(match + OFFSET_MatchStatus, &status, 4);

    uint64_t entities = 0;
    bool entitiesOk = _read(match + OFFSET_DictionaryEntities, &entities, 8);

    if (!lpOk || !statusOk || !entitiesOk) {
        return false;
    }

    bool statusValid = (status > 0 && status <= 10);
    bool entitiesValid = (entities == 0) || isVaildPtr(entities);
    bool lpValid = (lp == 0) || isVaildPtr(lp);

    bool result = statusValid && entitiesValid && lpValid;
    return result;
}

// ============================================================
// Player validator
// ============================================================
bool isValidPlayer(uint64_t player) {
    if (!isVaildPtr(player)) return false;
    uint64_t avatarMgr = 0;
    if (!_read(player + OFFSET_AvatarManager, &avatarMgr, 8)) return false;
    if (avatarMgr != 0 && !isVaildPtr(avatarMgr)) return false;

    uint32_t teamID = 0;
    if (!_read(player + OFFSET_TeamID, &teamID, 4)) return false;
    if (teamID == 0 || teamID > 100) return false;

    return true;
}

// ============================================================
// getMatchGame - Ultra resolver với nhiều offsets và scan
// ============================================================
uint64_t getMatchGame(uint64_t base) {
    if (base == 0) return 0;
    uint64_t initAddr = base + OFFSET_InitBase;
    ESPLog("[GL] InitBase addr = 0x%llX (base+0x%X)", initAddr, OFFSET_InitBase);

    uint64_t initVal = ReadAddr<uint64_t>(initAddr);
    ESPLog("[GL] *initAddr = 0x%llX", initVal);

    uint64_t result = 0;

    // Các offset thử cho static_fields trong Il2CppClass
    uint32_t staticOffsets[] = {0x5C, 0xB8, 0xC0, 0xD0, 0xE0, 0xF0, 0x100, 0x110};
    int nStatic = sizeof(staticOffsets)/sizeof(staticOffsets[0]);

    // Các offset thử cho CurrentMatch trong static_fields
    uint32_t currentMatchOffsets[] = {0x40, 0x48, 0x50, 0x58, 0x60, 0x68, 0x70, 0x78, 0x80, 0x88, 0x90};
    int nCM = sizeof(currentMatchOffsets)/sizeof(currentMatchOffsets[0]);

    // ── METHOD 1 ── initAddr = Il2CppClass* → +static_fields → thử nhiều CurrentMatch offsets
    for (int i = 0; i < nStatic; i++) {
        uint32_t soff = staticOffsets[i];
        uint64_t staticFields = 0;
        if (!_read(initAddr + soff, &staticFields, 8)) continue;
        if (!isVaildPtr(staticFields)) continue;
        ESPLog("[GL] M1[static=0x%X] staticFields=0x%llX", soff, staticFields);

        for (int j = 0; j < nCM; j++) {
            uint32_t cmoff = currentMatchOffsets[j];
            uint64_t match = ReadAddr<uint64_t>(staticFields + cmoff);
            if (match != 0 && isValidMatch(match)) {
                ESPLog("[GL] M1[static=0x%X][CM=0x%X] OK: Match=0x%llX", soff, cmoff, match);
                result = match;
                goto done;
            }
        }
    }

    // ── METHOD 2 ── *initAddr = Il2CppClass* → +static_fields → thử nhiều CurrentMatch offsets
    if (isVaildPtr(initVal)) {
        for (int i = 0; i < nStatic; i++) {
            uint32_t soff = staticOffsets[i];
            uint64_t staticFields = 0;
            if (!_read(initVal + soff, &staticFields, 8)) continue;
            if (!isVaildPtr(staticFields)) continue;
            ESPLog("[GL] M2[static=0x%X] staticFields=0x%llX", soff, staticFields);

            for (int j = 0; j < nCM; j++) {
                uint32_t cmoff = currentMatchOffsets[j];
                uint64_t match = ReadAddr<uint64_t>(staticFields + cmoff);
                if (match != 0 && isValidMatch(match)) {
                    ESPLog("[GL] M2[static=0x%X][CM=0x%X] OK: Match=0x%llX", soff, cmoff, match);
                    result = match;
                    goto done;
                }
            }
        }
    }

    // ── METHOD 3 ── *initAddr = GameManager instance → thử nhiều CurrentMatch offsets
    if (isVaildPtr(initVal)) {
        for (int j = 0; j < nCM; j++) {
            uint32_t cmoff = currentMatchOffsets[j];
            uint64_t match = ReadAddr<uint64_t>(initVal + cmoff);
            ESPLog("[GL] M3[CM=0x%X]: initVal=0x%llX match=0x%llX", cmoff, initVal, match);
            if (match != 0 && isValidMatch(match)) {
                ESPLog("[GL] M3[CM=0x%X] OK: Match=0x%llX", cmoff, match);
                result = match;
                goto done;
            }
        }
    }

    // ── METHOD 4 ── initAddr trực tiếp = GameManager instance → thử nhiều CurrentMatch offsets
    for (int j = 0; j < nCM; j++) {
        uint32_t cmoff = currentMatchOffsets[j];
        uint64_t match = ReadAddr<uint64_t>(initAddr + cmoff);
        ESPLog("[GL] M4[CM=0x%X]: match=0x%llX", cmoff, match);
        if (match != 0 && isValidMatch(match)) {
            ESPLog("[GL] M4[CM=0x%X] OK: Match=0x%llX", cmoff, match);
            result = match;
            goto done;
        }
    }

    // ── METHOD 5 ── initAddr trực tiếp = Match instance
    {
        ESPLog("[GL] M5: testing initAddr as Match");
        if (isValidMatch(initAddr)) {
            ESPLog("[GL] M5 OK: Match=0x%llX", initAddr);
            result = initAddr;
            goto done;
        }
    }

    // ── METHOD 6 ── *initAddr = Match instance
    if (isVaildPtr(initVal)) {
        ESPLog("[GL] M6: testing initVal as Match");
        if (isValidMatch(initVal)) {
            ESPLog("[GL] M6 OK: Match=0x%llX", initVal);
            result = initVal;
            goto done;
        }
    }

    // ── METHOD 7 ── Brute-force quanh InitBase ±256 bytes, thử nhiều CM offsets
    ESPLog("[GL] M7: Brute-force around InitBase");
    for (int off = -256; off <= 256; off += 8) {
        uint64_t addr = initAddr + off;
        uint64_t val = 0;
        if (!_read(addr, &val, 8)) continue;
        if (!isVaildPtr(val)) continue;

        // Thử coi val là GameManager → nhiều CurrentMatch offsets
        for (int j = 0; j < nCM; j++) {
            uint32_t cmoff = currentMatchOffsets[j];
            uint64_t match = ReadAddr<uint64_t>(val + cmoff);
            if (match != 0 && isValidMatch(match)) {
                ESPLog("[GL] M7[off=%d][CM=0x%X] OK: Match=0x%llX", off, cmoff, match);
                result = match;
                goto done;
            }
        }

        // Thử coi val là Match trực tiếp
        if (isValidMatch(val)) {
            ESPLog("[GL] M7[off=%d] direct OK: Match=0x%llX", off, val);
            result = val;
            goto done;
        }
    }

    // ── METHOD 8 ── Scan từ static_fields đã tìm được (0x108D31C38) trong vùng ±512 bytes
    // Log cho thấy staticFields=0x108D31C38 tồn tại, có thể CurrentMatch ở xa hơn
    {
        uint64_t knownStaticFields = 0;
        for (int i = 0; i < nStatic; i++) {
            uint32_t soff = staticOffsets[i];
            uint64_t sf = 0;
            if (!_read(initAddr + soff, &sf, 8)) continue;
            if (isVaildPtr(sf)) {
                knownStaticFields = sf;
                break;
            }
        }
        if (knownStaticFields != 0) {
            ESPLog("[GL] M8: Scanning from known staticFields=0x%llX", knownStaticFields);
            for (int off = -512; off <= 512; off += 8) {
                uint64_t ptr = 0;
                if (!_read(knownStaticFields + off, &ptr, 8)) continue;
                if (!isVaildPtr(ptr)) continue;
                if (isValidMatch(ptr)) {
                    ESPLog("[GL] M8[off=%d] OK: Match=0x%llX", off, ptr);
                    result = ptr;
                    goto done;
                }
            }
        }
    }

    // ── METHOD 9 ── Fallback offset cũ
    {
        uint64_t oldAddr = base + 0x9985B70;
        uint64_t oldVal = ReadAddr<uint64_t>(oldAddr);
        ESPLog("[GL] M9: oldOffset match=0x%llX", oldVal);
        if (isValidMatch(oldVal)) {
            ESPLog("[GL] M9 OK: Match=0x%llX", oldVal);
            result = oldVal;
            goto done;
        }
    }

    // ── METHOD 10 ── Scan heap region đầu tiên tìm Match signature
    // Chỉ scan 1 region đầu tiên hợp lệ để tránh lag
    {
        ESPLog("[GL] M10: Heap scan for Match signature");
        vm_address_t vmoffset = 0;
        vm_size_t vmsize = 0;
        uint32_t nesting_depth = 0;
        struct vm_region_submap_info_64 vbr;
        mach_msg_type_number_t vbrcount = VM_REGION_SUBMAP_INFO_COUNT_64;

        kern_return_t kr = vm_region_recurse_64(get_task, &vmoffset, &vmsize, &nesting_depth, (vm_region_recurse_info_t)&vbr, &vbrcount);
        if (kr == KERN_SUCCESS) {
            // Scan từng 8 bytes trong region đầu tiên (giới hạn 1MB để tránh lag)
            vm_size_t scanSize = vmsize > 0x100000 ? 0x100000 : vmsize;
            uint8_t* buffer = (uint8_t*)malloc(scanSize);
            if (buffer) {
                vm_size_t readSize = 0;
                kern_return_t readKr = vm_read_overwrite(get_task, vmoffset, scanSize, (vm_address_t)buffer, &readSize);
                if (readKr == KERN_SUCCESS && readSize == scanSize) {
                    for (vm_size_t i = 0; i < scanSize - 8; i += 8) {
                        uint64_t candidate = *(uint64_t*)(buffer + i);
                        if (!isVaildPtr(candidate)) continue;
                        if (isValidMatch(candidate)) {
                            ESPLog("[GL] M10[heap+0x%llX] OK: Match=0x%llX", (uint64_t)(vmoffset + i), candidate);
                            result = candidate;
                            break;
                        }
                    }
                }
                free(buffer);
            }
        }
        if (result != 0) goto done;
    }

done:
    if (result == 0) {
        ESPLog("[GL] getMatchGame: ALL METHODS FAILED");
    }
    return result;
}

// ============================================================
// getMatch
// ============================================================
uint64_t getMatch(uint64_t matchGame) {
    if (matchGame == 0) return 0;
    if (isValidMatch(matchGame)) {
        ESPLog("[GL] getMatch: matchGame is already Match");
        return matchGame;
    }
    uint64_t match = ReadAddr<uint64_t>(matchGame + OFFSET_CurrentMatch);
    ESPLog("[GL] getMatch: GameManager+CurrentMatch -> 0x%llX", match);
    if (isValidMatch(match)) return match;
    return 0;
}

// ============================================================
// getLocalPlayer
// ============================================================
uint64_t getLocalPlayer(uint64_t match) {
    if (!isVaildPtr(match)) return 0;
    uint64_t lp = ReadAddr<uint64_t>(match + OFFSET_LocalPlayer);
    ESPLog("[GL] LocalPlayer = 0x%llX", lp);
    return lp;
}

// ============================================================
// getPlayerList - Dictionary + List fallback
// ============================================================
int getPlayerList(uint64_t match, uint64_t* outPlayers, int maxCount) {
    if (!isVaildPtr(match) || outPlayers == nullptr || maxCount <= 0) return 0;

    uint64_t dict = ReadAddr<uint64_t>(match + OFFSET_DictionaryEntities);
    ESPLog("[GL] DictionaryEntities = 0x%llX", dict);
    if (!isVaildPtr(dict)) return 0;

    int count = 0;

    // Pattern A: Dictionary<ulong, Player>
    uint64_t entries = 0;
    int32_t dictCount = 0;

    uint32_t dictOffsets[] = {0x20, 0x28, 0x30, 0x18, 0x38};
    for (int di = 0; di < 5; di++) {
        uint32_t doff = dictOffsets[di];
        uint64_t tmpEntries = 0;
        if (!_read(dict + doff, &tmpEntries, 8)) continue;
        if (!isVaildPtr(tmpEntries)) continue;

        int32_t tmpCount = 0;
        if (!_read(tmpEntries + 0x18, &tmpCount, 4)) continue;
        if (tmpCount >= 0 && tmpCount <= 100) {
            entries = tmpEntries;
            dictCount = tmpCount;
            ESPLog("[GL] Dict entries found at +0x%X, count=%d", doff, dictCount);
            break;
        }
    }

    if (entries != 0 && dictCount > 0) {
        uint64_t items = 0;
        if (_read(entries + 0x20, &items, 8) && isVaildPtr(items)) {
            ESPLog("[GL] Dict items array = 0x%llX", items);
            for (int i = 0; i < dictCount && count < maxCount; i++) {
                uint64_t entry = 0;
                if (!_read(items + (i * 8), &entry, 8)) continue;
                if (!isVaildPtr(entry)) continue;

                uint64_t key = 0, value = 0;
                _read(entry + 0x0, &key, 8);
                _read(entry + 0x8, &value, 8);

                uint64_t player = 0;
                if (isValidPlayer(value)) {
                    player = value;
                } else if (isValidPlayer(key)) {
                    player = key;
                }

                if (player != 0) {
                    ESPLog("[GL] Dict[%d] player=0x%llX", i, player);
                    outPlayers[count++] = player;
                }
            }
        }
    }

    // Pattern B: List<Player> trực tiếp
    if (count == 0) {
        ESPLog("[GL] Trying List<Player> pattern");
        uint64_t listObj = dict;
        int32_t listSize = 0;
        if (_read(listObj + 0x18, &listSize, 4) && listSize > 0 && listSize <= 100) {
            uint64_t items = 0;
            if (_read(listObj + 0x20, &items, 8) && isVaildPtr(items)) {
                ESPLog("[GL] List size=%d items=0x%llX", listSize, items);
                for (int i = 0; i < listSize && count < maxCount; i++) {
                    uint64_t player = 0;
                    if (!_read(items + (i * 8), &player, 8)) continue;
                    if (isValidPlayer(player)) {
                        ESPLog("[GL] List[%d] player=0x%llX", i, player);
                        outPlayers[count++] = player;
                    }
                }
            }
        }
    }

    ESPLog("[GL] getPlayerList returned %d players", count);
    return count;
}

// ============================================================
// CameraMain
// ============================================================
uint64_t CameraMain(uint64_t matchGame) {
    if (matchGame == 0) return 0;

    if (isValidMatch(matchGame)) {
        uint64_t cam = ReadAddr<uint64_t>(matchGame + OFFSET_FollowCamera);
        ESPLog("[GL] CameraA (Match+FollowCamera) = 0x%llX", cam);
        if (isVaildPtr(cam)) {
            uint64_t camObj = ReadAddr<uint64_t>(cam + OFFSET_Camera);
            if (isVaildPtr(camObj)) return camObj;
        }
    }

    uint64_t cam = ReadAddr<uint64_t>(matchGame + OFFSET_FollowCamera);
    ESPLog("[GL] CameraB (GameManager+FollowCamera) = 0x%llX", cam);
    if (isVaildPtr(cam)) {
        uint64_t camObj = ReadAddr<uint64_t>(cam + OFFSET_Camera);
        if (isVaildPtr(camObj)) return camObj;
    }

    return 0;
}

// ============================================================
// Transform helpers
// ============================================================
uint64_t getHeadTransform(uint64_t player) {
    if (!isVaildPtr(player)) return 0;
    uint64_t avatarMgr = ReadAddr<uint64_t>(player + OFFSET_AvatarManager);
    if (!isVaildPtr(avatarMgr)) return 0;
    uint64_t avatar = ReadAddr<uint64_t>(avatarMgr + OFFSET_Avatar);
    if (!isVaildPtr(avatar)) return 0;
    uint64_t head = ReadAddr<uint64_t>(avatar + OFFSET_HeadCollider);
    return head;
}

uint64_t getToeTransform(uint64_t player) {
    if (!isVaildPtr(player)) return 0;
    uint64_t avatarMgr = ReadAddr<uint64_t>(player + OFFSET_AvatarManager);
    if (!isVaildPtr(avatarMgr)) return 0;
    uint64_t avatar = ReadAddr<uint64_t>(avatarMgr + OFFSET_Avatar);
    if (!isVaildPtr(avatar)) return 0;
    uint64_t toe = ReadAddr<uint64_t>(avatar + OFFSET_XPose);
    return toe;
}

uint32_t getTeamID(uint64_t player) {
    if (!isVaildPtr(player)) return 0;
    return ReadAddr<uint32_t>(player + OFFSET_TeamID);
}

bool isLocalTeamMate(uint64_t localPlayer, uint64_t player) {
    if (localPlayer == 0 || player == 0) return false;
    if (localPlayer == player) return true;
    uint32_t localTeam = getTeamID(localPlayer);
    uint32_t playerTeam = getTeamID(player);
    return (localTeam != 0 && localTeam == playerTeam);
}

NSString* getPlayerName(uint64_t player) {
    if (!isVaildPtr(player)) return @"???";
    uint64_t namePtr = ReadAddr<uint64_t>(player + OFFSET_Player_Name);
    return ReadIl2CppString(namePtr);
}

int get_CurHP(uint64_t player) {
    if (!isVaildPtr(player)) return 0;
    uint64_t attr = ReadAddr<uint64_t>(player + OFFSET_PlayerAttributes);
    if (!isVaildPtr(attr)) return 0;
    return ReadAddr<int>(attr + 0x28);
}

int get_MaxHP(uint64_t player) {
    if (!isVaildPtr(player)) return 0;
    uint64_t attr = ReadAddr<uint64_t>(player + OFFSET_PlayerAttributes);
    if (!isVaildPtr(attr)) return 0;
    return ReadAddr<int>(attr + 0x2C);
}

// ============================================================
// Camera helpers
// ============================================================
float* GetViewMatrix(uint64_t cameraMain) {
    static float matrix[16];
    if (!isVaildPtr(cameraMain)) return nullptr;
    uint64_t vm = ReadAddr<uint64_t>(cameraMain + OFFSET_ViewMatrix);
    if (!isVaildPtr(vm)) return nullptr;
    if (!_read(vm, matrix, 64)) return nullptr;
    return matrix;
}

float getCameraFov(uint64_t camera) {
    if (!isVaildPtr(camera)) return 60.0f;
    return ReadAddr<float>(camera + 0x40);
}

Vector3 getCameraPosition(uint64_t camera) {
    if (!isVaildPtr(camera)) return Vector3(0,0,0);
    uint64_t transform = ReadAddr<uint64_t>(camera + OFFSET_MainCameraTransform);
    return GetTransformPosition(transform);
}

Vector3 GetTransformPosition(uint64_t transform) {
    Vector3 pos(0,0,0);
    if (!isVaildPtr(transform)) return pos;

    struct TransformData {
        char pad[0x18];
        Vector3 pos;
    } data;

    if (_read(transform + 0x10, &data, sizeof(data))) {
        pos = data.pos;
    }
    return pos;
}
