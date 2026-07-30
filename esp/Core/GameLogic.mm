#import "GameLogic.h"
#include "Logger.h"
#include <cstring>

// ============================================================
// OFFSETS TỪ dump.cs IL2CPP
// ============================================================
// GameFacade (static class)
//   CurrentMatchGame: static field offset 0x8
//
// MatchGame : COWGameBase
//   m_Match: 0x90
//   m_CameraControllerManager: 0xD8
//
// EMKJHAJNPDH (Match)
//   PDBGEOANOEP (LocalPlayer): 0xD8
//   NGFEHJMADOJ (AllPlayers dict): 0x128
//   LNNHDLJFKLI (AlivePlayers dict): 0x130
//   CGLCNGIMJLF (PlayerList List<Player>): 0x158
//
// Player
//   LKDCAGNHDHP (HP uint): 0x244
//   DCEHPCDIEEL (MaxHP uint): 0x288
//   TeamModeID (uint): 0x3CC
//   OriginalNickName (string): 0x430
//   OKOLMFJKGEC (Transform): 0x698
//   ITransformNode array: 0x630 ~ 0x6C8
//
// CameraControllerManager : MonoBehaviour
//   BAGLCCLIOEK (Camera): 0x20
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

    // Unity Camera IL2CPP: thử nhiều offset
    uint64_t matrix = ReadAddr<uint64_t>(cameraMain + 0x30);
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

#pragma mark - Get MatchGame

uint64_t getMatchGame(uint64_t base) {
    uint64_t GameFacade_TypeInfo = ReadAddr<uint64_t>(base + 0x9985B70);

    if (!isVaildPtr(GameFacade_TypeInfo)) {
        ESPLog("[GL] GameFacade_TypeInfo not found at 0x9985B70");
        return 0;
    }

    ESPLog("[GL] GameFacade_TypeInfo = 0x%llX", GameFacade_TypeInfo);

    uint64_t static_fields = ReadAddr<uint64_t>(GameFacade_TypeInfo + 0xB8);
    if (!isVaildPtr(static_fields)) {
        ESPLog("[GL] static_fields INVALID");
        return 0;
    }
    ESPLog("[GL] static_fields = 0x%llX", static_fields);

    uint64_t matchGame = ReadAddr<uint64_t>(static_fields + 0x8);
    ESPLog("[GL] matchGame = 0x%llX", matchGame);

    return matchGame;
}

#pragma mark - Get Camera

uint64_t CameraMain(uint64_t matchGame) {
    if (!isVaildPtr(matchGame)) return 0;

    uint64_t camMgr = ReadAddr<uint64_t>(matchGame + 0xD8);
    if (!isVaildPtr(camMgr)) {
        ESPLog("[GL] CameraControllerManager INVALID");
        return 0;
    }
    ESPLog("[GL] CameraControllerManager = 0x%llX", camMgr);

    uint64_t camera = ReadAddr<uint64_t>(camMgr + 0x20);
    ESPLog("[GL] Camera = 0x%llX", camera);

    return camera;
}

#pragma mark - Get Match

uint64_t getMatch(uint64_t matchGame) {
    if (!isVaildPtr(matchGame)) return 0;
    uint64_t match = ReadAddr<uint64_t>(matchGame + 0x90);
    ESPLog("[GL] Match = 0x%llX", match);
    return match;
}

#pragma mark - Get Local Player

uint64_t getLocalPlayer(uint64_t match) {
    if (!isVaildPtr(match)) return 0;
    uint64_t localPlayer = ReadAddr<uint64_t>(match + 0xD8);
    ESPLog("[GL] LocalPlayer = 0x%llX", localPlayer);
    return localPlayer;
}

#pragma mark - Get Player List from List<Player>

int getPlayerList(uint64_t match, uint64_t* outPlayers, int maxCount) {
    if (!isVaildPtr(match) || !outPlayers || maxCount <= 0) return 0;

    uint64_t playerList = ReadAddr<uint64_t>(match + 0x158);
    if (!isVaildPtr(playerList)) {
        ESPLog("[GL] PlayerList INVALID");
        return 0;
    }
    ESPLog("[GL] PlayerList = 0x%llX", playerList);

    uint64_t items = ReadAddr<uint64_t>(playerList + 0x10);
    if (!isVaildPtr(items)) {
        ESPLog("[GL] PlayerList._items INVALID");
        return 0;
    }
    ESPLog("[GL] PlayerList._items = 0x%llX", items);

    int32_t count = 0;
    if (!_read(items + 0x10, &count, 4)) {
        ESPLog("[GL] Failed to read array length");
        return 0;
    }
    ESPLog("[GL] Player count = %d", count);

    if (count <= 0 || count > 1000) {
        ESPLog("[GL] Invalid player count: %d", count);
        return 0;
    }

    int validCount = 0;
    for (int i = 0; i < count && validCount < maxCount; i++) {
        uint64_t player = ReadAddr<uint64_t>(items + 0x18 + i * 8);
        if (isVaildPtr(player)) {
            outPlayers[validCount++] = player;
        }
    }

    ESPLog("[GL] Valid players = %d", validCount);
    return validCount;
}

#pragma mark - Get Player Data

uint64_t getHeadTransform(uint64_t player) {
    if (!isVaildPtr(player)) return 0;

    // OKOLMFJKGEC tại 0x698 (Transform)
    uint64_t transform = ReadAddr<uint64_t>(player + 0x698);
    if (isVaildPtr(transform)) {
        return transform;
    }

    // Fallback: brute-force ITransformNode array 0x630~0x6C8
    for (int i = 0; i < 20; i++) {
        uint64_t ptr = ReadAddr<uint64_t>(player + 0x630 + i * 8);
        if (isVaildPtr(ptr)) {
            return ptr;
        }
    }
    return 0;
}

uint64_t getToeTransform(uint64_t player) {
    if (!isVaildPtr(player)) return 0;

    float minY = 999999.0f;
    uint64_t bestToe = 0;

    for (int i = 0; i < 20; i++) {
        uint64_t ptr = ReadAddr<uint64_t>(player + 0x630 + i * 8);
        if (!isVaildPtr(ptr)) continue;

        Vector3 pos = getPositionExt(ptr);
        if (pos.y < minY && pos.y > -1000.0f) {
            minY = pos.y;
            bestToe = ptr;
        }
    }
    return bestToe;
}

uint32_t getTeamID(uint64_t player) {
    if (!isVaildPtr(player)) return 0xFF;
    uint32_t teamID = 0;
    _read(player + 0x3CC, &teamID, 4);
    return teamID;
}

bool isLocalTeamMate(uint64_t localPlayer, uint64_t player) {
    if (!isVaildPtr(localPlayer) || !isVaildPtr(player)) return false;
    return getTeamID(localPlayer) == getTeamID(player);
}

NSString* getPlayerName(uint64_t player) {
    if (!isVaildPtr(player)) return @"???";
    uint64_t namePtr = ReadAddr<uint64_t>(player + 0x430);
    if (isVaildPtr(namePtr)) {
        return ReadIl2CppString(namePtr);
    }
    return @"???";
}

int get_CurHP(uint64_t player) {
    if (!isVaildPtr(player)) return 0;
    uint32_t hp = 0;
    if (_read(player + 0x244, &hp, 4)) {
        return (int)(hp & 0xFFFF);
    }
    return 0;
}

int get_MaxHP(uint64_t player) {
    if (!isVaildPtr(player)) return 0;
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

    uint64_t transform = ReadAddr<uint64_t>(camera + 0x30);
    if (isVaildPtr(transform)) {
        pos = getPositionExt(transform);
    }
    return pos;
}
