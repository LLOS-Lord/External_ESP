#include "GameLogic.h"
#include "MemoryUtils.h"
#include "MemoryPattern.h"
#include "OffsetResolver.h"
#include "Logger.h"
#include "Offsets.h"
#include <cmath>
#include <chrono>
#include <cstring>

// ==========================================
// GLOBALS
// ==========================================
static uint64_t s_matchGame = 0;
static float s_viewMatrix[16];
static Vector3 s_cameraPos;

// ==========================================
// HELPERS
// ==========================================

static bool tryReadU64(uint64_t addr, uint64_t* out) {
    return _read(addr, out, 8);
}

static bool tryReadU32(uint64_t addr, uint32_t* out) {
    return _read(addr, out, 4);
}

static bool tryReadU8(uint64_t addr, uint8_t* out) {
    return _read(addr, out, 1);
}

static bool tryReadFloat(uint64_t addr, float* out) {
    return _read(addr, out, 4);
}

// ==========================================
// LOBBY DETECTION
// ==========================================

bool IsAtLobby(void) {
    if (Module_Base == 0) return true;

    uint64_t p0 = 0;
    if (!tryReadU64(Module_Base + OFFSET_GWorld, &p0) || p0 == 0 || !isVaildPtr(p0)) {
        return true; // GWorld invalid = lobby
    }

    uint64_t p1 = 0;
    if (!tryReadU64(p0 + OFFSET_GWorld_To_Match, &p1) || p1 == 0 || !isVaildPtr(p1)) {
        return true; // Match pointer invalid = lobby
    }

    uint64_t validCheck = 0;
    if (!tryReadU64(p1 + OFFSET_Match_Valid, &validCheck) || validCheck == 0 || !isVaildPtr(validCheck)) {
        return true; // Validity check failed = lobby
    }

    return false; // In game
}

// ==========================================
// MATCH GAME
// ==========================================

uint64_t getMatchGame() {
    if (Module_Base == 0) return 0;

    // Return cached if valid
    if (s_matchGame != 0) {
        uint64_t check = 0;
        if (tryReadU64(s_matchGame + OFFSET_Match_Valid, &check) && check != 0 && isVaildPtr(check)) {
            return s_matchGame;
        }
        s_matchGame = 0;
    }

    // Resolve offsets if needed
    if (!g_resolved.resolved) {
        resolveOffsets(Module_Base, 256ULL * 1024 * 1024);
    }

    uint64_t p0 = 0;
    if (!tryReadU64(Module_Base + OFFSET_GWorld, &p0) || p0 == 0 || !isVaildPtr(p0)) {
        return 0;
    }

    uint64_t p1 = 0;
    if (!tryReadU64(p0 + OFFSET_GWorld_To_Match, &p1) || p1 == 0 || !isVaildPtr(p1)) {
        return 0;
    }

    // Validate via OFFSET_Match_Valid
    uint64_t validCheck = 0;
    if (!tryReadU64(p1 + OFFSET_Match_Valid, &validCheck) || validCheck == 0) {
        return 0;
    }

    s_matchGame = p1;
    ESPLog("[GL] getMatchGame: 0x%llX (valid=0x%llX)", p1, validCheck);
    return p1;
}

// ==========================================
// LOCAL PLAYER
// ==========================================

uint64_t getLocalPlayer(uint64_t match) {
    if (match == 0) return 0;
    // Try legacy offset first, then fallback to heuristic
    uint64_t local = ReadAddr<uint64_t>(match + g_resolved.off_Match_To_LocalPlayer);
    if (local != 0 && isVaildPtr(local)) {
        return local;
    }
    // Fallback: try common UE local player offsets
    const uint32_t LOCAL_OFFS[] = {0x30, 0x38, 0x40, 0x48, 0x50, 0x58, 0x60, 0x68, 0x70, 0x78, 0x80, 0x88, 0x90, 0x98, 0xA0};
    for (size_t i = 0; i < sizeof(LOCAL_OFFS)/sizeof(LOCAL_OFFS[0]); i++) {
        uint64_t candidate = ReadAddr<uint64_t>(match + LOCAL_OFFS[i]);
        if (candidate != 0 && isVaildPtr(candidate)) {
            // Validate: check if it looks like a player object (has reasonable bone/HP data)
            uint64_t hpTest = 0;
            if (tryReadU64(candidate + OFFSET_Player_HP_Base, &hpTest) && hpTest != 0) {
                g_resolved.off_Match_To_LocalPlayer = LOCAL_OFFS[i];
                return candidate;
            }
        }
    }
    return 0;
}

// ==========================================
// CAMERA / VIEW MATRIX
// ==========================================

uint64_t GetCameraObject() {
    uint64_t match = getMatchGame();
    if (match == 0) return 0;

    // Try chain from matchGame: +0x10 -> +0x48 -> +0x80 -> +0xC0
    uint64_t step1 = ReadAddr<uint64_t>(match + OFFSET_Cam_Chain1);
    if (step1 == 0 || !isVaildPtr(step1)) return 0;

    uint64_t step2 = ReadAddr<uint64_t>(step1 + OFFSET_Cam_Chain2);
    if (step2 == 0 || !isVaildPtr(step2)) return 0;

    uint64_t step3 = ReadAddr<uint64_t>(step2 + OFFSET_Cam_Chain3);
    if (step3 == 0 || !isVaildPtr(step3)) return 0;

    // step3 + OFFSET_Cam_Matrix is the matrix address
    uint64_t matrixAddr = step3 + OFFSET_Cam_Matrix;
    if (!isVaildPtr(matrixAddr)) return 0;

    return matrixAddr;
}

float* GetViewMatrix(uint64_t camera) {
    if (camera == 0) {
        // Try to get camera object automatically
        camera = GetCameraObject();
        if (camera == 0) return nullptr;
    }
    // camera parameter here is actually the matrix address from GetCameraObject
    if (!_read(camera, s_viewMatrix, 64)) {
        return nullptr;
    }
    return s_viewMatrix;
}

float getCameraFov(uint64_t camera) {
    // FOV not directly available in report; return default
    return 90.0f;
}

Vector3 getCameraPosition(uint64_t camera) {
    // Camera position extraction - try to read from matrix inverse or fallback
    // For now, return cached or zero
    return s_cameraPos;
}

// ==========================================
// BONE POSITION
// ==========================================

Vector3 GetBonePosition(uint64_t player, uint32_t boneOffset) {
    Vector3 pos = {0, 0, 0};
    if (player == 0) return pos;

    // In UE, bone offset may point to an FTransform struct or a pointer to it.
    // Try pointer first.
    uint64_t bonePtr = ReadAddr<uint64_t>(player + boneOffset);
    if (bonePtr != 0 && isVaildPtr(bonePtr)) {
        // Assume FTransform layout: Rotation(16) at 0x0, Translation(12) at 0x10, Scale(12) at 0x20
        if (_read(bonePtr + 0x10, &pos, 12)) {
            return pos;
        }
    }

    // Try inline struct at player+boneOffset
    if (_read(player + boneOffset + 0x10, &pos, 12)) {
        return pos;
    }

    // Last resort: read as Vector3 directly
    _read(player + boneOffset, &pos, 12);
    return pos;
}

// ==========================================
// PLAYER ATTRIBUTES
// ==========================================

bool IsPlayerBot(uint64_t player) {
    if (player == 0) return false;
    uint8_t val = 0;
    if (!tryReadU8(player + OFFSET_Player_IsBot, &val)) return false;
    return val != 0;
}

bool IsPlayerVisible(uint64_t player) {
    if (player == 0) return false;
    uint64_t p1 = ReadAddr<uint64_t>(player + OFFSET_Player_IsVisible);
    if (p1 == 0 || !isVaildPtr(p1)) return false;
    uint64_t p2 = ReadAddr<uint64_t>(p1 + OFFSET_Player_IsVisible_1);
    if (p2 == 0 || !isVaildPtr(p2)) return false;
    uint8_t val = 0;
    if (!tryReadU8(p2 + OFFSET_Player_IsVisible_2, &val)) return false;
    return val != 0;
}

uint32_t GetPlayerHP(uint64_t player, int index) {
    if (player == 0) return 0;
    // Chain: [[[PlayerObject + 0x70] + 0x10] + (Index * 8) + 0x20] + 0x18
    uint64_t step1 = ReadAddr<uint64_t>(player + OFFSET_Player_HP_Base);
    if (step1 == 0 || !isVaildPtr(step1)) return 0;

    uint64_t step2 = ReadAddr<uint64_t>(step1 + OFFSET_HP_Base_1);
    if (step2 == 0 || !isVaildPtr(step2)) return 0;

    uint64_t step3 = ReadAddr<uint64_t>(step2 + (index * OFFSET_HP_IndexMul) + OFFSET_HP_Base_2);
    if (step3 == 0 || !isVaildPtr(step3)) return 0;

    uint32_t hp = 0;
    tryReadU32(step3 + OFFSET_HP_Final, &hp);
    return hp;
}

uint32_t GetPlayerMaxHP(uint64_t player, int index) {
    // Try index+1 for max HP, or same logic with different index
    // If index=0 is HP, index=1 might be MaxHP in the same array
    return GetPlayerHP(player, index + 1);
}

NSString* getPlayerName(uint64_t player) {
    if (player == 0) return @"???";
    // Try legacy name offset
    uint64_t nameAddr = ReadAddr<uint64_t>(player + OFFSET_NickName);
    if (nameAddr != 0 && isVaildPtr(nameAddr)) {
        char buf[64] = {};
        _read(nameAddr + 0x14, buf, 32);
        if (buf[0] != 0) return [NSString stringWithUTF8String:buf];
    }
    return @"???";
}

uint32_t getPlayerTeamID(uint64_t player) {
    if (player == 0) return 0;
    return readU32(player + OFFSET_TeamID);
}

bool isValidPlayer(uint64_t player) {
    if (player == 0) return false;
    if (!isVaildPtr(player)) return false;
    // Additional validation: check if bone offsets are readable
    uint64_t test = 0;
    return tryReadU64(player + OFFSET_Bone_Head, &test);
}

// ==========================================
// PLAYER LIST
// ==========================================

std::vector<PlayerInfo> getPlayerList() {
    std::vector<PlayerInfo> list;
    uint64_t match = getMatchGame();
    if (match == 0) return list;

    uint64_t localPlayer = getLocalPlayer(match);
    int localTeam = 0;
    if (localPlayer != 0) {
        localTeam = getPlayerTeamID(localPlayer);
    }

    // Try legacy dictionary approach first
    uint64_t gm = 0;
    if (g_resolved.hasInstance && g_resolved.gameManagerInstance != 0) {
        gm = g_resolved.gameManagerInstance;
    } else {
        // Try to read GWorld as GameManager-like structure
        tryReadU64(Module_Base + OFFSET_GWorld, &gm);
    }

    if (gm != 0 && isVaildPtr(gm)) {
        uint64_t dict = ReadAddr<uint64_t>(gm + g_resolved.off_GM_To_Dict);
        if (dict != 0 && isVaildPtr(dict)) {
            uint64_t entries = ReadAddr<uint64_t>(dict + 0x18);
            int count = readU32(dict + 0x20);
            if (count > 0 && count <= 200 && entries != 0 && isVaildPtr(entries)) {
                for (int i = 0; i < count; i++) {
                    uint64_t playerPtr = ReadAddr<uint64_t>(entries + i * 8);
                    if (playerPtr == 0 || playerPtr == localPlayer) continue;
                    if (!isValidPlayer(playerPtr)) continue;

                    PlayerInfo p;
                    p.address = playerPtr;
                    p.head     = GetBonePosition(playerPtr, OFFSET_Bone_Head);
                    p.toe      = GetBonePosition(playerPtr, OFFSET_Bone_RToe);
                    p.hip      = GetBonePosition(playerPtr, OFFSET_Bone_Hip);
                    p.lHand    = GetBonePosition(playerPtr, OFFSET_Bone_LHand);
                    p.rHand    = GetBonePosition(playerPtr, OFFSET_Bone_RHand);
                    p.lElbow   = GetBonePosition(playerPtr, OFFSET_Bone_LElbow);
                    p.rElbow   = GetBonePosition(playerPtr, OFFSET_Bone_RElbow);
                    p.lShoulder = GetBonePosition(playerPtr, OFFSET_Bone_LShoulder);
                    p.rShoulder = GetBonePosition(playerPtr, OFFSET_Bone_RShoulder);
                    p.lAnkle   = GetBonePosition(playerPtr, OFFSET_Bone_LAnkle);
                    p.rAnkle   = GetBonePosition(playerPtr, OFFSET_Bone_RAnkle);
                    p.lToe     = GetBonePosition(playerPtr, OFFSET_Bone_LToe);
                    p.rToe     = GetBonePosition(playerPtr, OFFSET_Bone_RToe);

                    p.hp       = GetPlayerHP(playerPtr, 0);
                    p.maxHp    = GetPlayerMaxHP(playerPtr, 0);
                    p.team     = getPlayerTeamID(playerPtr);
                    p.isBot    = IsPlayerBot(playerPtr);
                    p.isVisible = IsPlayerVisible(playerPtr);
                    p.isDead   = (p.hp <= 0 || p.hp > 9999);
                    p.name     = [getPlayerName(playerPtr) UTF8String];

                    list.push_back(p);
                }
                return list;
            }
        }
    }

    // Fallback: scan match object for player pointers
    for (uint32_t off = 0x100; off < 0x800; off += 8) {
        uint64_t candidate = ReadAddr<uint64_t>(match + off);
        if (candidate == 0 || candidate == localPlayer) continue;
        if (!isValidPlayer(candidate)) continue;

        // Check if it has valid bone data
        Vector3 head = GetBonePosition(candidate, OFFSET_Bone_Head);
        if (head.x == 0 && head.y == 0 && head.z == 0) continue;

        PlayerInfo p;
        p.address = candidate;
        p.head     = head;
        p.toe      = GetBonePosition(candidate, OFFSET_Bone_RToe);
        p.hip      = GetBonePosition(candidate, OFFSET_Bone_Hip);
        p.lHand    = GetBonePosition(candidate, OFFSET_Bone_LHand);
        p.rHand    = GetBonePosition(candidate, OFFSET_Bone_RHand);
        p.lElbow   = GetBonePosition(candidate, OFFSET_Bone_LElbow);
        p.rElbow   = GetBonePosition(candidate, OFFSET_Bone_RElbow);
        p.lShoulder = GetBonePosition(candidate, OFFSET_Bone_LShoulder);
        p.rShoulder = GetBonePosition(candidate, OFFSET_Bone_RShoulder);
        p.lAnkle   = GetBonePosition(candidate, OFFSET_Bone_LAnkle);
        p.rAnkle   = GetBonePosition(candidate, OFFSET_Bone_RAnkle);
        p.lToe     = GetBonePosition(candidate, OFFSET_Bone_LToe);
        p.rToe     = GetBonePosition(candidate, OFFSET_Bone_RToe);

        p.hp       = GetPlayerHP(candidate, 0);
        p.maxHp    = GetPlayerMaxHP(candidate, 0);
        p.team     = getPlayerTeamID(candidate);
        p.isBot    = IsPlayerBot(candidate);
        p.isVisible = IsPlayerVisible(candidate);
        p.isDead   = (p.hp <= 0 || p.hp > 9999);
        p.name     = [getPlayerName(candidate) UTF8String];

        list.push_back(p);

        if (list.size() >= 100) break; // Safety limit
    }

    return list;
}

// ==========================================
// WORLD TO SCREEN
// ==========================================

Vector3 WorldToScreen(Vector3 pos, float* matrix, float width, float height) {
    Vector3 out = {0, 0, 0};
    if (!matrix) return out;

    float x = pos.x * matrix[0] + pos.y * matrix[4] + pos.z * matrix[8]  + matrix[12];
    float y = pos.x * matrix[1] + pos.y * matrix[5] + pos.z * matrix[9]  + matrix[13];
    float w = pos.x * matrix[3] + pos.y * matrix[7] + pos.z * matrix[11] + matrix[15];

    if (w < 0.01f) {
        out.z = w; // Mark as behind camera
        return out;
    }

    float ndcX = x / w;
    float ndcY = y / w;

    out.x = (ndcX + 1.0f) * 0.5f * width;
    out.y = (1.0f - ndcY) * 0.5f * height;
    out.z = w;
    return out;
}

bool worldToScreen(Vector3 pos, float* outX, float* outY, int screenW, int screenH, uint64_t match) {
    float* matrix = GetViewMatrix(0);
    if (!matrix) return false;

    Vector3 screen = WorldToScreen(pos, matrix, (float)screenW, (float)screenH);
    if (screen.z < 0.01f) return false;

    *outX = screen.x;
    *outY = screen.y;
    return true;
}

// ==========================================
// LIFECYCLE
// ==========================================

void setupGameLogic(mach_port_t task) {
    get_task = task;
    ESPLog("[GL] GameLogic setup complete");
}

void resetGameLogicCache() {
    s_matchGame = 0;
    memset(s_viewMatrix, 0, sizeof(s_viewMatrix));
    ESPLog("[GL] Cache reset");
}
