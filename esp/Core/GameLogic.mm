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

    // Nếu bất kỳ read nào fail → không phải Match
    if (!lpOk || !statusOk || !entitiesOk) {
        ESPLog("[GL] isValidMatch(0x%llX): read FAIL (lp=%s status=%s entities=%s)",
               match, lpOk?"OK":"FAIL", statusOk?"OK":"FAIL", entitiesOk?"OK":"FAIL");
        return false;
    }

    // Match đang chạy thì status > 0 (thường 1-5)
    bool statusValid = (status > 0 && status <= 10);

    // DictionaryEntities phải là pointer hợp lệ (hoặc 0 nếu chưa có ai)
    bool entitiesValid = (entities == 0) || isVaildPtr(entities);

    // LocalPlayer = 0 là OK (chưa spawn), nhưng nếu != 0 thì phải valid
    bool lpValid = (lp == 0) || isVaildPtr(lp);

    bool result = statusValid && entitiesValid && lpValid;
    ESPLog("[GL] isValidMatch(0x%llX): lp=0x%llX status=%u entities=0x%llX -> %s",
           match, lp, status, entities, result?"PASS":"FAIL");
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
    // TeamID thường 1-50
    if (teamID == 0 || teamID > 100) return false;

    return true;
}

// ============================================================
// getMatchGame - Multi-path resolver
// ============================================================
uint64_t getMatchGame(uint64_t base) {
    if (base == 0) return 0;
    uint64_t initAddr = base + OFFSET_InitBase;
    ESPLog("[GL] InitBase addr = 0x%llX (base+0x%X)", initAddr, OFFSET_InitBase);

    uint64_t initVal = ReadAddr<uint64_t>(initAddr);
    ESPLog("[GL] *initAddr = 0x%llX", initVal);

    uint64_t result = 0;

    // Các offset thử cho static_fields trong Il2CppClass
    uint32_t staticOffsets[] = {0x5C, 0xB8, 0xC0, 0xD0, 0xE0, 0xF0};
    int nStatic = sizeof(staticOffsets)/sizeof(staticOffsets[0]);

    // ── METHOD 1 ── initAddr = Il2CppClass* → +static_fields → +CurrentMatch
    for (int i = 0; i < nStatic; i++) {
        uint32_t soff = staticOffsets[i];
        uint64_t staticFields = 0;
        if (!_read(initAddr + soff, &staticFields, 8)) continue;
        if (!isVaildPtr(staticFields)) continue;
        uint64_t match = ReadAddr<uint64_t>(staticFields + OFFSET_CurrentMatch);
        ESPLog("[GL] M1[static=0x%X] staticFields=0x%llX match=0x%llX", soff, staticFields, match);
        if (isValidMatch(match)) {
            ESPLog("[GL] M1[static=0x%X] OK: Match=0x%llX", soff, match);
            result = match;
            goto done;
        }
    }

    // ── METHOD 2 ── *initAddr = Il2CppClass* → +static_fields → +CurrentMatch
    if (isVaildPtr(initVal)) {
        for (int i = 0; i < nStatic; i++) {
            uint32_t soff = staticOffsets[i];
            uint64_t staticFields = 0;
            if (!_read(initVal + soff, &staticFields, 8)) continue;
            if (!isVaildPtr(staticFields)) continue;
            uint64_t match = ReadAddr<uint64_t>(staticFields + OFFSET_CurrentMatch);
            ESPLog("[GL] M2[static=0x%X] staticFields=0x%llX match=0x%llX", soff, staticFields, match);
            if (isValidMatch(match)) {
                ESPLog("[GL] M2[static=0x%X] OK: Match=0x%llX", soff, match);
                result = match;
                goto done;
            }
        }
    }

    // ── METHOD 3 ── *initAddr = GameManager instance → +CurrentMatch
    if (isVaildPtr(initVal)) {
        uint64_t match = ReadAddr<uint64_t>(initVal + OFFSET_CurrentMatch);
        ESPLog("[GL] M3: initVal=0x%llX match=0x%llX", initVal, match);
        if (isValidMatch(match)) {
            ESPLog("[GL] M3 OK: Match=0x%llX", match);
            result = match;
            goto done;
        }
    }

    // ── METHOD 4 ── initAddr trực tiếp = GameManager instance → +CurrentMatch
    {
        uint64_t match = ReadAddr<uint64_t>(initAddr + OFFSET_CurrentMatch);
        ESPLog("[GL] M4: match=0x%llX", match);
        if (isValidMatch(match)) {
            ESPLog("[GL] M4 OK: Match=0x%llX", match);
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

    // ── METHOD 7 ── Brute-force quanh InitBase ±128 bytes
    ESPLog("[GL] M7: Brute-force around InitBase");
    for (int off = -128; off <= 128; off += 8) {
        uint64_t addr = initAddr + off;
        uint64_t val = 0;
        if (!_read(addr, &val, 8)) continue;
        if (!isVaildPtr(val)) continue;
        // Thử coi val là GameManager → +CurrentMatch
        uint64_t match = ReadAddr<uint64_t>(val + OFFSET_CurrentMatch);
        if (isValidMatch(match)) {
            ESPLog("[GL] M7[off=%d] OK: Match=0x%llX", off, match);
            result = match;
            goto done;
        }
        // Thử coi val là Match trực tiếp
        if (isValidMatch(val)) {
            ESPLog("[GL] M7[off=%d] direct OK: Match=0x%llX", off, val);
            result = val;
            goto done;
        }
    }

    // ── METHOD 8 ── Fallback offset cũ
    {
        uint64_t oldAddr = base + 0x9985B70;
        uint64_t oldVal = ReadAddr<uint64_t>(oldAddr);
        ESPLog("[GL] M8: oldOffset match=0x%llX", oldVal);
        if (isValidMatch(oldVal)) {
            ESPLog("[GL] M8 OK: Match=0x%llX", oldVal);
            result = oldVal;
            goto done;
        }
    }

done:
    if (result == 0) {
        ESPLog("[GL] getMatchGame: ALL METHODS FAILED");
    }
    return result;
}

// ============================================================
// getMatch - nếu matchGame đã là Match thì dùng luôn
// ============================================================
uint64_t getMatch(uint64_t matchGame) {
    if (matchGame == 0) return 0;
    if (isValidMatch(matchGame)) {
        ESPLog("[GL] getMatch: matchGame is already Match");
        return matchGame;
    }
    // Nếu là GameManager thì +CurrentMatch
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
// getPlayerList - Dictionary (thử entries/keys/values) + List fallback
// ============================================================
int getPlayerList(uint64_t match, uint64_t* outPlayers, int maxCount) {
    if (!isVaildPtr(match) || outPlayers == nullptr || maxCount <= 0) return 0;

    uint64_t dict = ReadAddr<uint64_t>(match + OFFSET_DictionaryEntities);
    ESPLog("[GL] DictionaryEntities = 0x%llX", dict);
    if (!isVaildPtr(dict)) return 0;

    int count = 0;

    // ── Pattern A: Dictionary<ulong, Player> ──
    // entries (List<DictionaryEntry>) tại +0x20
    // hoặc +0x28 tùy version
    uint64_t entries = 0;
    uint64_t keys = 0;
    uint64_t values = 0;
    int32_t dictCount = 0;

    // Thử đọc entries tại các offset phổ biến
    uint32_t dictOffsets[] = {0x20, 0x28, 0x30, 0x18};
    for (int di = 0; di < 4; di++) {
        uint32_t doff = dictOffsets[di];
        uint64_t tmpEntries = 0;
        if (!_read(dict + doff, &tmpEntries, 8)) continue;
        if (!isVaildPtr(tmpEntries)) continue;

        // Thử đọc count tại entries+0x18 (List._size)
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
        // List items array tại +0x20
        uint64_t items = 0;
        if (_read(entries + 0x20, &items, 8) && isVaildPtr(items)) {
            ESPLog("[GL] Dict items array = 0x%llX", items);
            for (int i = 0; i < dictCount && count < maxCount; i++) {
                uint64_t entry = 0;
                if (!_read(items + (i * 8), &entry, 8)) continue;
                if (!isVaildPtr(entry)) continue;

                // Thử key tại +0x0, value tại +0x8
                uint64_t key = 0, value = 0;
                _read(entry + 0x0, &key, 8);
                _read(entry + 0x8, &value, 8);

                // Thử ngược: key tại +0x8, value tại +0x0
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

    // ── Pattern B: List<Player> trực tiếp ──
    if (count == 0) {
        ESPLog("[GL] Trying List<Player> pattern");
        uint64_t listObj = dict; // DictionaryEntities có thể là List trực tiếp
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
// CameraMain - Multi-path
// ============================================================
uint64_t CameraMain(uint64_t matchGame) {
    if (matchGame == 0) return 0;

    // Path A: matchGame là Match → +FollowCamera
    if (isValidMatch(matchGame)) {
        uint64_t cam = ReadAddr<uint64_t>(matchGame + OFFSET_FollowCamera);
        ESPLog("[GL] CameraA (Match+FollowCamera) = 0x%llX", cam);
        if (isVaildPtr(cam)) {
            uint64_t camObj = ReadAddr<uint64_t>(cam + OFFSET_Camera);
            if (isVaildPtr(camObj)) return camObj;
        }
    }

    // Path B: matchGame là GameManager → +FollowCamera
    uint64_t cam = ReadAddr<uint64_t>(matchGame + OFFSET_FollowCamera);
    ESPLog("[GL] CameraB (GameManager+FollowCamera) = 0x%llX", cam);
    if (isVaildPtr(cam)) {
        uint64_t camObj = ReadAddr<uint64_t>(cam + OFFSET_Camera);
        if (isVaildPtr(camObj)) return camObj;
    }

    // Fallback cũ
    uint64_t camMgr = ReadAddr<uint64_t>(matchGame + OFFSET_FollowCamera);
    if (isVaildPtr(camMgr)) {
        uint64_t camObj = ReadAddr<uint64_t>(camMgr + OFFSET_Camera);
        if (isVaildPtr(camObj)) return camObj;
    }

    return 0;
}

// ============================================================
// Transform helpers (giữ nguyên)
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
    return ReadAddr<int>(attr + 0x28); // offset HP trong PlayerAttributes
}

int get_MaxHP(uint64_t player) {
    if (!isVaildPtr(player)) return 0;
    uint64_t attr = ReadAddr<uint64_t>(player + OFFSET_PlayerAttributes);
    if (!isVaildPtr(attr)) return 0;
    return ReadAddr<int>(attr + 0x2C); // offset MaxHP
}

// ============================================================
// Camera helpers (giữ nguyên)
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
    return ReadAddr<float>(camera + 0x40); // FOV offset thường
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
