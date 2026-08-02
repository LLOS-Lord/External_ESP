#import "GameLogic.h"
#include "Logger.h"
#include "Offsets.h"
#include <cstring>

// ============================================================
// OFFSETS UPDATED FROM Offsets.cs
// ============================================================
// Cấu trúc suy luận từ offsets mới:
//   [ModuleBase + InitBase] → GameManager / StaticClass pointer
//   + CurrentMatch(0x50)    → Match
//   + DictionaryEntities(0x68) → Player Dictionary/List
//
// Match:
//   + LocalPlayer(0x94)     → LocalPlayer
//   + MatchStatus(0x8C)     → Match status
//
// Player:
//   + TeamID(0x29C)         → Team ID
//   + Player_Name(0x2DC)    → Nickname string
//   + AvatarManager(0x4C0)  → AvatarManager
//   + AvatarManager + Avatar(0xA8) → Avatar → Transform
//   + XPose(0x78)           → Transform fallback
//   + PlayerAttributes(0x4B0) → Attributes (HP có thể ở đây)
//
// Camera:
//   + FollowCamera(0x450)   → từ Base hoặc Match
//   + Camera(0x18)          → Camera object
//   + ViewMatrix(0xE8)      → View matrix
// ============================================================

// ---- CẤU TRÚC LIST<T> TRONG IL2CPP ----
// List<T>:
//   0x00: vtable
//   0x08: monitor
//   0x10: T[] _items
//   0x18: int _size
//   0x1C: int _version
//
// Array<T>:
//   0x00: vtable
//   0x08: monitor
//   0x10: int32 length
//   0x18: T elements[]

// ---- CẤU TRÚC Dictionary<TKey, TValue> TRONG IL2CPP ----
// Dictionary:
//   0x00: vtable
//   0x08: monitor  
//   0x10: int count
//   0x18: int version
//   0x1C: int freeList
//   0x20: int freeCount
//   0x28: Entry[] entries
//   0x30: int[] buckets

#pragma mark - Helper: Read String

NSString* ReadIl2CppString(uint64_t strAddr) {
    if (!isVaildPtr(strAddr)) return @"???";
    // Il2CppString: vtable(8) + monitor(8) + length(4) + chars[]
    int32_t len = 0;
    if (!_read(strAddr + 0x10, &len, 4)) return @"???";
    if (len <= 0 || len > 256) return @"???";
    uint16_t buffer[256];
    if (!_read(strAddr + 0x14, buffer, len * 2)) return @"???";
    buffer[len] = 0;
    return [[NSString alloc] initWithBytes:buffer length:len*2 encoding:NSUTF16LittleEndianStringEncoding];
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

#pragma mark - Get MatchGame (CurrentMatch)

uint64_t getMatchGame(uint64_t base) {
    // Cách 1: InitBase là pointer trực tiếp đến GameManager
    uint64_t initPtr = ReadAddr<uint64_t>(base + OFFSET_InitBase);
    if (!isVaildPtr(initPtr)) {
        ESPLog("[GL] InitBase pointer INVALID at 0x%llX", base + OFFSET_InitBase);
        return 0;
    }
    ESPLog("[GL] InitBase = 0x%llX", initPtr);

    // Thử: initPtr + StaticClass(0x5C) → static fields area
    uint64_t staticFields = initPtr + OFFSET_StaticClass;
    ESPLog("[GL] staticFields = 0x%llX", staticFields);

    uint64_t currentMatch = ReadAddr<uint64_t>(staticFields + OFFSET_CurrentMatch);
    ESPLog("[GL] currentMatch (method 1) = 0x%llX", currentMatch);

    // Nếu không hợp lệ, thử cách 2: StaticClass là pointer
    if (!isVaildPtr(currentMatch)) {
        uint64_t staticFieldsPtr = ReadAddr<uint64_t>(initPtr + OFFSET_StaticClass);
        if (isVaildPtr(staticFieldsPtr)) {
            currentMatch = ReadAddr<uint64_t>(staticFieldsPtr + OFFSET_CurrentMatch);
            ESPLog("[GL] currentMatch (method 2) = 0x%llX", currentMatch);
        }
    }

    // Nếu vẫn không hợp lệ, thử cách 3: InitBase trực tiếp là static fields
    if (!isVaildPtr(currentMatch)) {
        currentMatch = ReadAddr<uint64_t>(initPtr + OFFSET_CurrentMatch);
        ESPLog("[GL] currentMatch (method 3) = 0x%llX", currentMatch);
    }

    return currentMatch;
}

#pragma mark - Get Camera

uint64_t CameraMain(uint64_t matchGame) {
    if (!isVaildPtr(matchGame)) return 0;

    // Thử: matchGame + FollowCamera(0x450) → CameraController/FollowCamera
    uint64_t followCam = ReadAddr<uint64_t>(matchGame + OFFSET_FollowCamera);
    if (isVaildPtr(followCam)) {
        ESPLog("[GL] FollowCamera = 0x%llX", followCam);

        // FollowCamera + Camera(0x18) → Camera
        uint64_t camera = ReadAddr<uint64_t>(followCam + OFFSET_Camera);
        if (isVaildPtr(camera)) {
            ESPLog("[GL] Camera (via FollowCamera) = 0x%llX", camera);
            return camera;
        }
    }

    // Fallback: thử offset cũ CameraControllerManager
    uint64_t camMgr = ReadAddr<uint64_t>(matchGame + 0xD8);
    if (isVaildPtr(camMgr)) {
        ESPLog("[GL] CameraControllerManager (fallback) = 0x%llX", camMgr);
        uint64_t camera = ReadAddr<uint64_t>(camMgr + 0x20);
        if (isVaildPtr(camera)) {
            ESPLog("[GL] Camera (fallback) = 0x%llX", camera);
            return camera;
        }
    }

    ESPLog("[GL] Camera NOT FOUND");
    return 0;
}

#pragma mark - Get Match

uint64_t getMatch(uint64_t matchGame) {
    // Trong offsets mới, CurrentMatch chính là Match
    // Nên matchGame đã là match rồi, nhưng vẫn giữ hàm này để tương thích
    if (!isVaildPtr(matchGame)) return 0;

    // Thử đọc MatchStatus để xác nhận đây là match hợp lệ
    uint32_t matchStatus = 0;
    _read(matchGame + OFFSET_MatchStatus, &matchStatus, 4);
    ESPLog("[GL] Match = 0x%llX, Status = %d", matchGame, matchStatus);

    return matchGame;
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

    // Thử đọc DictionaryEntities như List<Player>
    uint64_t dictEntities = ReadAddr<uint64_t>(match + OFFSET_DictionaryEntities);
    if (!isVaildPtr(dictEntities)) {
        ESPLog("[GL] DictionaryEntities INVALID");
        return 0;
    }
    ESPLog("[GL] DictionaryEntities = 0x%llX", dictEntities);

    // Thử cấu trúc List<T>
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

    // Thử cấu trúc Dictionary<TKey, TValue>
    // Dictionary + 0x28 → Entry[] entries
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

    // Cách 1: Player → AvatarManager(0x4C0) → Avatar(0xA8) → Transform
    uint64_t avatarMgr = ReadAddr<uint64_t>(player + OFFSET_AvatarManager);
    if (isVaildPtr(avatarMgr)) {
        uint64_t avatar = ReadAddr<uint64_t>(avatarMgr + OFFSET_Avatar);
        if (isVaildPtr(avatar)) {
            // Avatar thường chứa Transform tại offset đầu hoặc có thể lấy từ internal
            uint64_t transform = ReadAddr<uint64_t>(avatar + OFFSET_Avatar_Data);
            if (isVaildPtr(transform)) {
                ESPLog("[GL] HeadTransform via AvatarManager = 0x%llX", transform);
                return transform;
            }
            // Thử offset 0x30 (thường là Transform trong Unity components)
            transform = ReadAddr<uint64_t>(avatar + 0x30);
            if (isVaildPtr(transform)) {
                ESPLog("[GL] HeadTransform via Avatar+0x30 = 0x%llX", transform);
                return transform;
            }
        }
    }

    // Cách 2: Thử XPose(0x78) → Transform
    uint64_t xpose = ReadAddr<uint64_t>(player + OFFSET_XPose);
    if (isVaildPtr(xpose)) {
        ESPLog("[GL] HeadTransform via XPose = 0x%llX", xpose);
        return xpose;
    }

    // Cách 3: Fallback brute-force quanh các offset biết
    for (int i = 0; i < 30; i++) {
        uint64_t ptr = ReadAddr<uint64_t>(player + 0x600 + i * 8);
        if (isVaildPtr(ptr)) {
            Vector3 pos = getPositionExt(ptr);
            if (pos.y > -1000.0f && pos.y < 10000.0f) {
                ESPLog("[GL] HeadTransform fallback[%d] = 0x%llX pos=(%.1f,%.1f,%.1f)", i, ptr, pos.x, pos.y, pos.z);
                return ptr;
            }
        }
    }

    ESPLog("[GL] HeadTransform NOT FOUND");
    return 0;
}

uint64_t getToeTransform(uint64_t player) {
    if (!isVaildPtr(player)) return 0;

    // Thử tìm transform thấp nhất (chân) trong các bone/transform
    float minY = 999999.0f;
    uint64_t bestToe = 0;

    // Thử qua AvatarManager nếu có nhiều bones
    uint64_t avatarMgr = ReadAddr<uint64_t>(player + OFFSET_AvatarManager);
    if (isVaildPtr(avatarMgr)) {
        uint64_t avatar = ReadAddr<uint64_t>(avatarMgr + OFFSET_Avatar);
        if (isVaildPtr(avatar)) {
            // Thử đọc mảng transforms từ avatar
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

    // Fallback: dùng head transform nếu không tìm được toe
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

    // Thử đọc từ PlayerAttributes(0x4B0)
    uint64_t attributes = ReadAddr<uint64_t>(player + OFFSET_PlayerAttributes);
    if (isVaildPtr(attributes)) {
        uint32_t hp = 0;
        // HP thường ở offset đầu trong attributes, thử 0x0, 0x4, 0x8
        if (_read(attributes + 0x0, &hp, 4) && hp > 0 && hp < 10000) {
            return (int)(hp & 0xFFFF);
        }
        if (_read(attributes + 0x4, &hp, 4) && hp > 0 && hp < 10000) {
            return (int)(hp & 0xFFFF);
        }
        if (_read(attributes + 0x8, &hp, 4) && hp > 0 && hp < 10000) {
            return (int)(hp & 0xFFFF);
        }
    }

    // Fallback: offset cũ
    uint32_t hp = 0;
    if (_read(player + 0x244, &hp, 4)) {
        return (int)(hp & 0xFFFF);
    }
    return 0;
}

int get_MaxHP(uint64_t player) {
    if (!isVaildPtr(player)) return 0;

    // Thử đọc từ PlayerAttributes(0x4B0)
    uint64_t attributes = ReadAddr<uint64_t>(player + OFFSET_PlayerAttributes);
    if (isVaildPtr(attributes)) {
        uint32_t maxHP = 0;
        // MaxHP thường sau HP một chút
        if (_read(attributes + 0x4, &maxHP, 4) && maxHP > 0 && maxHP < 10000) {
            return (int)(maxHP & 0xFFFF);
        }
        if (_read(attributes + 0x8, &maxHP, 4) && maxHP > 0 && maxHP < 10000) {
            return (int)(maxHP & 0xFFFF);
        }
        if (_read(attributes + 0xC, &maxHP, 4) && maxHP > 0 && maxHP < 10000) {
            return (int)(maxHP & 0xFFFF);
        }
    }

    // Fallback: offset cũ
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

    // Thử MainCameraTransform(0x24C)
    uint64_t transform = ReadAddr<uint64_t>(camera + OFFSET_MainCameraTransform);
    if (isVaildPtr(transform)) {
        pos = getPositionExt(transform);
        ESPLog("[GL] CameraPos via MainCameraTransform = (%.1f,%.1f,%.1f)", pos.x, pos.y, pos.z);
        return pos;
    }

    // Fallback: offset cũ 0x30
    transform = ReadAddr<uint64_t>(camera + 0x30);
    if (isVaildPtr(transform)) {
        pos = getPositionExt(transform);
        ESPLog("[GL] CameraPos via fallback = (%.1f,%.1f,%.1f)", pos.x, pos.y, pos.z);
    }
    return pos;
}
