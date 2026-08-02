#import "GameLogic.h"
#include "Logger.h"
#include "Offsets.h"
#include <cstring>

// ============================================================
// FIXED: Multi-path resolver for InitBase / Match / Player
// ============================================================
// Offsets.cs structure analysis:
//   InitBase(0xA988FDC) may be:
//     A) Pointer to Il2CppClass*  → +StaticClass(0x5C) → static_fields → +CurrentMatch(0x50)
//     B) Pointer to GameManager   → +CurrentMatch(0x50) → Match
//     C) GameManager instance itself → +CurrentMatch(0x50) → Match
//     D) Pointer to Match directly
//
//   Match:
//     + MatchStatus(0x8C)      → uint32
//     + LocalPlayer(0x94)      → LocalPlayer*
//     + DictionaryEntities(0x68) → List/Dict of players
//
//   Player:
//     + TeamID(0x29C)          → uint32
//     + Player_Name(0x2DC)     → Il2CppString*
//     + AvatarManager(0x4C0)   → AvatarManager* → +Avatar(0xA8) → Transform
//     + XPose(0x78)            → Transform* fallback
//     + PlayerAttributes(0x4B0) → Attributes* (HP/MaxHP)
// ============================================================

#pragma mark - Helper: Read String

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

#pragma mark - Helper: Validate Match Structure

bool isValidMatch(uint64_t match) {
    if (!isVaildPtr(match)) return false;
    // Match should have LocalPlayer at 0x94 that is a valid pointer (or null when not spawned)
    uint64_t lp = ReadAddr<uint64_t>(match + OFFSET_LocalPlayer);
    // Also check MatchStatus at 0x8C is a small integer
    uint32_t status = 0;
    _read(match + OFFSET_MatchStatus, &status, 4);
    // Status usually 0-5 (lobby, loading, playing, ended...)
    // If LocalPlayer is valid OR status is in reasonable range, accept
    bool lpOk = (lp == 0) || isVaildPtr(lp);
    bool statusOk = status <= 10;
    return lpOk && statusOk;
}

#pragma mark - Helper: Get View Matrix from Camera

float* GetViewMatrix(uint64_t cameraMain) {
    if (!isVaildPtr(cameraMain)) return nullptr;

    // Thử offset ViewMatrix mới (0xE8)
    uint64_t matrix = ReadAddr<uint64_t>(cameraMain + OFFSET_ViewMatrix);
    if (isVaildPtr(matrix)) {
        static float matrixV[16];
        if (_read(matrix + 0x10, matrixV, sizeof(float) * 16)) {
            return matrixV;
        }
    }

    // Fallback: thử các offset cũ của Unity Camera
    matrix = ReadAddr<uint64_t>(cameraMain + 0x30);
    if (!isVaildPtr(matrix)) {
        matrix = ReadAddr<uint64_t>(cameraMain + 0x40);
        if (!isVaildPtr(matrix)) {
            matrix = ReadAddr<uint64_t>(cameraMain + 0x50);
            if (!isVaildPtr(matrix)) return nullptr;
        }
    }

    uint64_t matrix2 = ReadAddr<uint64_t>(matrix + 0x18);
    if (!isVaildPtr(matrix2)) {
        matrix2 = ReadAddr<uint64_t>(matrix + 0x10);
        if (!isVaildPtr(matrix2)) return nullptr;
    }

    static float matrixV[16];
    if (_read(matrix2 + 0x10, matrixV, sizeof(float) * 16)) {
        return matrixV;
    }
    return nullptr;
}

#pragma mark - Get MatchGame (CurrentMatch) — MULTI-PATH

uint64_t getMatchGame(uint64_t base) {
    if (base == 0) return 0;
    uint64_t initAddr = base + OFFSET_InitBase;
    ESPLog("[GL] InitBase addr = 0x%llX (base+0x%X)", initAddr, OFFSET_InitBase);

    uint64_t result = 0;

    // ── METHOD 1 ──
    // initAddr = Il2CppClass*  → +StaticClass(0x5C) = static_fields* → +CurrentMatch(0x50) = Match*
    {
        uint64_t staticFields = ReadAddr<uint64_t>(initAddr + OFFSET_StaticClass);
        if (isVaildPtr(staticFields)) {
            uint64_t match = ReadAddr<uint64_t>(staticFields + OFFSET_CurrentMatch);
            if (isValidMatch(match)) {
                ESPLog("[GL] Method1 OK: Match=0x%llX", match);
                result = match;
            }
        }
    }
    if (result) return result;

    // ── METHOD 2 ──
    // *initAddr = Il2CppClass* → +StaticClass → static_fields → +CurrentMatch
    {
        uint64_t cls = ReadAddr<uint64_t>(initAddr);
        ESPLog("[GL] Method2: *initAddr = 0x%llX", cls);
        if (isVaildPtr(cls)) {
            uint64_t staticFields = ReadAddr<uint64_t>(cls + OFFSET_StaticClass);
            if (isVaildPtr(staticFields)) {
                uint64_t match = ReadAddr<uint64_t>(staticFields + OFFSET_CurrentMatch);
                if (isValidMatch(match)) {
                    ESPLog("[GL] Method2 OK: Match=0x%llX", match);
                    result = match;
                }
            }
        }
    }
    if (result) return result;

    // ── METHOD 3 ──
    // *initAddr = GameManager instance → +CurrentMatch(0x50) = Match*
    {
        uint64_t mgr = ReadAddr<uint64_t>(initAddr);
        if (isVaildPtr(mgr)) {
            uint64_t match = ReadAddr<uint64_t>(mgr + OFFSET_CurrentMatch);
            if (isValidMatch(match)) {
                ESPLog("[GL] Method3 OK: Match=0x%llX", match);
                result = match;
            }
        }
    }
    if (result) return result;

    // ── METHOD 4 ──
    // initAddr itself = GameManager instance → +CurrentMatch(0x50) = Match*
    {
        uint64_t match = ReadAddr<uint64_t>(initAddr + OFFSET_CurrentMatch);
        if (isValidMatch(match)) {
            ESPLog("[GL] Method4 OK: Match=0x%llX", match);
            result = match;
        }
    }
    if (result) return result;

    // ── METHOD 5 ──
    // initAddr itself = Match instance directly (CurrentMatch offset is inside it)
    // Try using initAddr as Match and validate
    {
        if (isValidMatch(initAddr)) {
            ESPLog("[GL] Method5 OK: InitBase IS Match=0x%llX", initAddr);
            result = initAddr;
        }
    }
    if (result) return result;

    // ── METHOD 6 ──
    // *initAddr = Match instance directly
    {
        uint64_t match = ReadAddr<uint64_t>(initAddr);
        if (isValidMatch(match)) {
            ESPLog("[GL] Method6 OK: *InitBase = Match=0x%llX", match);
            result = match;
        }
    }
    if (result) return result;

    // ── METHOD 7 ──
    // Brute-force around InitBase ± 0x100 looking for a pointer that resolves to valid Match
    {
        ESPLog("[GL] Method7: Brute-force around InitBase...");
        for (int i = -32; i <= 32 && !result; i++) {
            uint64_t testAddr = initAddr + i * 8;
            uint64_t testPtr  = ReadAddr<uint64_t>(testAddr);
            if (!isVaildPtr(testPtr)) continue;

            // 7a: testPtr as Il2CppClass → static → CurrentMatch
            uint64_t sf = ReadAddr<uint64_t>(testPtr + OFFSET_StaticClass);
            if (isVaildPtr(sf)) {
                uint64_t match = ReadAddr<uint64_t>(sf + OFFSET_CurrentMatch);
                if (isValidMatch(match)) {
                    ESPLog("[GL] Method7a[%d] OK: Match=0x%llX", i, match);
                    result = match; break;
                }
            }

            // 7b: testPtr as GameManager → CurrentMatch
            uint64_t match2 = ReadAddr<uint64_t>(testPtr + OFFSET_CurrentMatch);
            if (isValidMatch(match2)) {
                ESPLog("[GL] Method7b[%d] OK: Match=0x%llX", i, match2);
                result = match2; break;
            }

            // 7c: testPtr as Match
            if (isValidMatch(testPtr)) {
                ESPLog("[GL] Method7c[%d] OK: Match=0x%llX", i, testPtr);
                result = testPtr; break;
            }
        }
    }
    if (result) return result;

    // ── METHOD 8 ──
    // Try old hardcoded offsets as ultimate fallback (in case offsets.cs is for different build)
    {
        ESPLog("[GL] Method8: Fallback to old offsets...");
        uint64_t oldPtr = ReadAddr<uint64_t>(base + 0x9985B70);
        if (isVaildPtr(oldPtr)) {
            uint64_t oldStatic = ReadAddr<uint64_t>(oldPtr + 0xB8);
            if (isVaildPtr(oldStatic)) {
                uint64_t oldMatch = ReadAddr<uint64_t>(oldStatic + 0x8);
                if (isValidMatch(oldMatch)) {
                    ESPLog("[GL] Method8 OK: Match=0x%llX", oldMatch);
                    result = oldMatch;
                }
            }
        }
    }

    if (!result) {
        ESPLog("[GL] ALL methods FAILED to find Match");
    }
    return result;
}

#pragma mark - Get Camera

uint64_t CameraMain(uint64_t matchGame) {
    if (!isVaildPtr(matchGame)) return 0;

    // Path A: Match + FollowCamera(0x450) → FollowCamera* + Camera(0x18) → Camera*
    uint64_t followCam = ReadAddr<uint64_t>(matchGame + OFFSET_FollowCamera);
    if (isVaildPtr(followCam)) {
        uint64_t camera = ReadAddr<uint64_t>(followCam + OFFSET_Camera);
        if (isVaildPtr(camera)) {
            ESPLog("[GL] Camera (FollowCamera path) = 0x%llX", camera);
            return camera;
        }
    }

    // Path B: Try if matchGame is actually GameManager and FollowCamera is there
    uint64_t match = ReadAddr<uint64_t>(matchGame + OFFSET_CurrentMatch);
    if (isValidMatch(match)) {
        followCam = ReadAddr<uint64_t>(match + OFFSET_FollowCamera);
        if (isVaildPtr(followCam)) {
            uint64_t camera = ReadAddr<uint64_t>(followCam + OFFSET_Camera);
            if (isVaildPtr(camera)) return camera;
        }
    }

    // Fallback: old CameraControllerManager path
    uint64_t camMgr = ReadAddr<uint64_t>(matchGame + 0xD8);
    if (isVaildPtr(camMgr)) {
        uint64_t camera = ReadAddr<uint64_t>(camMgr + 0x20);
        if (isVaildPtr(camera)) {
            ESPLog("[GL] Camera (fallback old) = 0x%llX", camera);
            return camera;
        }
    }

    ESPLog("[GL] Camera NOT FOUND");
    return 0;
}

#pragma mark - Get Match (validate / extract from GameManager if needed)

uint64_t getMatch(uint64_t matchGame) {
    if (!isVaildPtr(matchGame)) return 0;

    // If matchGame is already a valid Match, return it
    if (isValidMatch(matchGame)) {
        return matchGame;
    }

    // If matchGame is GameManager, try to get Match from CurrentMatch
    uint64_t match = ReadAddr<uint64_t>(matchGame + OFFSET_CurrentMatch);
    if (isValidMatch(match)) {
        ESPLog("[GL] getMatch extracted from GameManager: 0x%llX", match);
        return match;
    }

    // Ultimate fallback: old offset
    uint64_t oldMatch = ReadAddr<uint64_t>(matchGame + 0x90);
    if (isValidMatch(oldMatch)) return oldMatch;

    ESPLog("[GL] getMatch FAILED");
    return 0;
}

#pragma mark - Get Local Player

uint64_t getLocalPlayer(uint64_t match) {
    if (!isVaildPtr(match)) return 0;
    uint64_t localPlayer = ReadAddr<uint64_t>(match + OFFSET_LocalPlayer);
    ESPLog("[GL] LocalPlayer = 0x%llX", localPlayer);
    return localPlayer;
}

#pragma mark - Get Player List from DictionaryEntities

int getPlayerList(uint64_t match, uint64_t* outPlayers, int maxCount) {
    if (!isVaildPtr(match) || !outPlayers || maxCount <= 0) return 0;

    uint64_t dictEntities = ReadAddr<uint64_t>(match + OFFSET_DictionaryEntities);
    if (!isVaildPtr(dictEntities)) {
        ESPLog("[GL] DictionaryEntities INVALID");
        return 0;
    }
    ESPLog("[GL] DictionaryEntities = 0x%llX", dictEntities);

    // Try List<T> structure
    uint64_t items = ReadAddr<uint64_t>(dictEntities + 0x10);
    if (isVaildPtr(items)) {
        int32_t count = 0;
        if (_read(items + 0x10, &count, 4)) {
            ESPLog("[GL] Player count (List) = %d", count);
            if (count > 0 && count <= 1000) {
                int validCount = 0;
                for (int i = 0; i < count && validCount < maxCount; i++) {
                    uint64_t player = ReadAddr<uint64_t>(items + 0x18 + i * 8);
                    if (isVaildPtr(player)) {
                        outPlayers[validCount++] = player;
                    }
                }
                ESPLog("[GL] Valid players (List) = %d", validCount);
                return validCount;
            }
        }
    }

    // Try Dictionary<TKey, TValue> structure
    uint64_t entries = ReadAddr<uint64_t>(dictEntities + 0x28);
    if (isVaildPtr(entries)) {
        int32_t count = 0;
        if (_read(dictEntities + 0x10, &count, 4)) {
            ESPLog("[GL] Player count (Dictionary) = %d", count);
            if (count > 0 && count <= 1000) {
                int validCount = 0;
                for (int i = 0; i < count && validCount < maxCount; i++) {
                    // Entry: hashCode(4) + next(4) + key(8) + value(8) = 24 bytes
                    uint64_t player = ReadAddr<uint64_t>(entries + 0x18 + i * 0x18 + 0x10);
                    if (isVaildPtr(player)) {
                        outPlayers[validCount++] = player;
                    }
                }
                ESPLog("[GL] Valid players (Dictionary) = %d", validCount);
                return validCount;
            }
        }
    }

    ESPLog("[GL] Failed to read player list");
    return 0;
}

#pragma mark - Get Player Data

uint64_t getHeadTransform(uint64_t player) {
    if (!isVaildPtr(player)) return 0;

    // Path 1: AvatarManager(0x4C0) → Avatar(0xA8) → Avatar_Data(0x14) → Transform
    uint64_t avatarMgr = ReadAddr<uint64_t>(player + OFFSET_AvatarManager);
    if (isVaildPtr(avatarMgr)) {
        uint64_t avatar = ReadAddr<uint64_t>(avatarMgr + OFFSET_Avatar);
        if (isVaildPtr(avatar)) {
            uint64_t transform = ReadAddr<uint64_t>(avatar + OFFSET_Avatar_Data);
            if (isVaildPtr(transform)) {
                ESPLog("[GL] HeadTransform via AvatarManager = 0x%llX", transform);
                return transform;
            }
            transform = ReadAddr<uint64_t>(avatar + 0x30);
            if (isVaildPtr(transform)) {
                ESPLog("[GL] HeadTransform via Avatar+0x30 = 0x%llX", transform);
                return transform;
            }
        }
    }

    // Path 2: XPose(0x78) → Transform
    uint64_t xpose = ReadAddr<uint64_t>(player + OFFSET_XPose);
    if (isVaildPtr(xpose)) {
        ESPLog("[GL] HeadTransform via XPose = 0x%llX", xpose);
        return xpose;
    }

    // Fallback: brute-force scan for transform with valid position
    for (int i = 0; i < 40; i++) {
        uint64_t ptr = ReadAddr<uint64_t>(player + 0x600 + i * 8);
        if (!isVaildPtr(ptr)) continue;
        Vector3 pos = getPositionExt(ptr);
        if (pos.y > -1000.0f && pos.y < 10000.0f && pos.x != 0 && pos.z != 0) {
            ESPLog("[GL] HeadTransform fallback[%d] = 0x%llX pos=(%.1f,%.1f,%.1f)", i, ptr, pos.x, pos.y, pos.z);
            return ptr;
        }
    }

    ESPLog("[GL] HeadTransform NOT FOUND");
    return 0;
}

uint64_t getToeTransform(uint64_t player) {
    if (!isVaildPtr(player)) return 0;

    float minY = 999999.0f;
    uint64_t bestToe = 0;

    uint64_t avatarMgr = ReadAddr<uint64_t>(player + OFFSET_AvatarManager);
    if (isVaildPtr(avatarMgr)) {
        uint64_t avatar = ReadAddr<uint64_t>(avatarMgr + OFFSET_Avatar);
        if (isVaildPtr(avatar)) {
            for (int i = 0; i < 20; i++) {
                uint64_t ptr = ReadAddr<uint64_t>(avatar + 0x40 + i * 8);
                if (!isVaildPtr(ptr)) continue;
                Vector3 pos = getPositionExt(ptr);
                if (pos.y < minY && pos.y > -1000.0f) {
                    minY = pos.y;
                    bestToe = ptr;
                }
            }
        }
    }

    if (bestToe != 0) {
        ESPLog("[GL] ToeTransform = 0x%llX", bestToe);
        return bestToe;
    }

    return getHeadTransform(player);
}

uint32_t getTeamID(uint64_t player) {
    if (!isVaildPtr(player)) return 0xFF;
    uint32_t teamID = 0;
    _read(player + OFFSET_TeamID, &teamID, 4);
    return teamID;
}

bool isLocalTeamMate(uint64_t localPlayer, uint64_t player) {
    if (!isVaildPtr(localPlayer) || !isVaildPtr(player)) return false;
    return getTeamID(localPlayer) == getTeamID(player);
}

NSString* getPlayerName(uint64_t player) {
    if (!isVaildPtr(player)) return @"???";
    uint64_t namePtr = ReadAddr<uint64_t>(player + OFFSET_Player_Name);
    if (isVaildPtr(namePtr)) {
        return ReadIl2CppString(namePtr);
    }
    return @"???";
}

int get_CurHP(uint64_t player) {
    if (!isVaildPtr(player)) return 0;

    uint64_t attributes = ReadAddr<uint64_t>(player + OFFSET_PlayerAttributes);
    if (isVaildPtr(attributes)) {
        uint32_t hp = 0;
        for (int off = 0; off <= 0x10; off += 4) {
            if (_read(attributes + off, &hp, 4) && hp > 0 && hp < 10000) {
                return (int)(hp & 0xFFFF);
            }
        }
    }

    uint32_t hp = 0;
    if (_read(player + 0x244, &hp, 4)) {
        return (int)(hp & 0xFFFF);
    }
    return 0;
}

int get_MaxHP(uint64_t player) {
    if (!isVaildPtr(player)) return 0;

    uint64_t attributes = ReadAddr<uint64_t>(player + OFFSET_PlayerAttributes);
    if (isVaildPtr(attributes)) {
        uint32_t maxHP = 0;
        for (int off = 0x4; off <= 0x14; off += 4) {
            if (_read(attributes + off, &maxHP, 4) && maxHP > 0 && maxHP < 10000) {
                return (int)(maxHP & 0xFFFF);
            }
        }
    }

    uint32_t maxHP = 0;
    if (_read(player + 0x288, &maxHP, 4)) {
        return (int)(maxHP & 0xFFFF);
    }
    return 100;
}

#pragma mark - Get Camera Data

float getCameraFov(uint64_t camera) {
    if (!isVaildPtr(camera)) return 60.0f;
    float fov = 60.0f;
    _read(camera + 0x48, &fov, 4);
    if (fov < 10.0f || fov > 150.0f) {
        _read(camera + 0x58, &fov, 4);
    }
    return fov;
}

Vector3 getCameraPosition(uint64_t camera) {
    Vector3 pos = {0, 0, 0};
    if (!isVaildPtr(camera)) return pos;

    uint64_t transform = ReadAddr<uint64_t>(camera + OFFSET_MainCameraTransform);
    if (isVaildPtr(transform)) {
        pos = getPositionExt(transform);
        ESPLog("[GL] CameraPos via MainCameraTransform = (%.1f,%.1f,%.1f)", pos.x, pos.y, pos.z);
        return pos;
    }

    transform = ReadAddr<uint64_t>(camera + 0x30);
    if (isVaildPtr(transform)) {
        pos = getPositionExt(transform);
        ESPLog("[GL] CameraPos via fallback = (%.1f,%.1f,%.1f)", pos.x, pos.y, pos.z);
    }
    return pos;
}
