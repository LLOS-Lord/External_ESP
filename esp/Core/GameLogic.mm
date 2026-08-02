#include "GameLogic.h"
#include "Offsets.h"
#include "Logger.h"
#include <cstring>

// ============================================================
// Il2Cpp static field offsets to try (varies by Il2Cpp version)
// ============================================================
static const int STATIC_CLASS_OFFSETS[] = {0x5C, 0xB8, 0xC0, 0xD0, 0xE0};
static const int NUM_STATIC_OFFSETS = sizeof(STATIC_CLASS_OFFSETS) / sizeof(STATIC_CLASS_OFFSETS[0]);

// ============================================================
// isValidMatch  –  tighten checks to avoid false positives
// ============================================================
inline bool isValidMatch(uint64_t match) {
    if (!isVaildPtr(match)) return false;

    uint64_t lp      = ReadAddr<uint64_t>(match + OFFSET_LocalPlayer);
    uint32_t status  = ReadAddr<uint32_t>(match + OFFSET_MatchStatus);
    uint64_t dict    = ReadAddr<uint64_t>(match + OFFSET_DictionaryEntities);

    // Status must be a real game state (1=Lobby, 2=Loading, 3=Playing, 4=End, ...)
    if (status == 0 || status > 10) return false;

    // If local player has spawned, pointer must be valid
    if (lp != 0 && !isVaildPtr(lp)) return false;

    // Dictionary/List of entities should exist and look like a valid object
    if (dict != 0 && !isVaildPtr(dict)) return false;

    return true;
}

// ============================================================
// isValidPlayer – basic sanity checks on a player object
// ============================================================
bool isValidPlayer(uint64_t player) {
    if (!isVaildPtr(player)) return false;

    uint64_t namePtr = ReadAddr<uint64_t>(player + OFFSET_Player_Name);
    if (namePtr != 0 && !isVaildPtr(namePtr)) return false;

    uint64_t avatarMgr = ReadAddr<uint64_t>(player + OFFSET_AvatarManager);
    if (avatarMgr != 0 && !isVaildPtr(avatarMgr)) return false;

    uint32_t team = ReadAddr<uint32_t>(player + OFFSET_TeamID);
    if (team > 10000) return false; // sanity

    return true;
}

// ============================================================
// getMatchGame – try multiple ways to locate the Match pointer
// ============================================================
uint64_t getMatchGame(uint64_t base) {
    if (base == 0) return 0;

    uint64_t initAddr = base + OFFSET_InitBase;
    ESPLog("[GL] InitBase addr = 0x%llX (base+0x%X)", initAddr, OFFSET_InitBase);

    // --- Method 1: direct pointer ---
    uint64_t direct = ReadAddr<uint64_t>(initAddr);
    if (isValidMatch(direct)) {
        ESPLog("[GL] Method1: Direct Match OK");
        return direct;
    }

    // --- Method 2: *initAddr -> Il2CppClass -> static_fields -> Match ---
    uint64_t cls = ReadAddr<uint64_t>(initAddr);
    ESPLog("[GL] Method2: *initAddr = 0x%llX", cls);
    if (isVaildPtr(cls)) {
        for (int i = 0; i < NUM_STATIC_OFFSETS; i++) {
            int off = STATIC_CLASS_OFFSETS[i];
            uint64_t staticFields = ReadAddr<uint64_t>(cls + off);
            if (!isVaildPtr(staticFields)) continue;

            uint64_t match = ReadAddr<uint64_t>(staticFields + OFFSET_CurrentMatch);
            ESPLog("[GL] Method2: staticFields[0x%X]=0x%llX -> match=0x%llX", off, staticFields, match);
            if (isValidMatch(match)) {
                ESPLog("[GL] Method2 OK (off=0x%X): Match=0x%llX", off, match);
                return match;
            }
        }
    }

    // --- Method 3: initAddr -> GameManager -> Match ---
    uint64_t gm = ReadAddr<uint64_t>(initAddr);
    if (isVaildPtr(gm)) {
        uint64_t match = ReadAddr<uint64_t>(gm + OFFSET_CurrentMatch);
        ESPLog("[GL] Method3: gm=0x%llX -> match=0x%llX", gm, match);
        if (isValidMatch(match)) {
            ESPLog("[GL] Method3 OK: Match=0x%llX", match);
            return match;
        }
    }

    // --- Method 4: initAddr IS GameManager ---
    {
        uint64_t match = ReadAddr<uint64_t>(initAddr + OFFSET_CurrentMatch);
        ESPLog("[GL] Method4: initAddr+0x%X -> match=0x%llX", OFFSET_CurrentMatch, match);
        if (isValidMatch(match)) {
            ESPLog("[GL] Method4 OK: Match=0x%llX", match);
            return match;
        }
    }

    // --- Method 5: initAddr -> Class -> static -> Match (double indirection) ---
    uint64_t clsPtr = ReadAddr<uint64_t>(initAddr);
    if (isVaildPtr(clsPtr)) {
        uint64_t realCls = ReadAddr<uint64_t>(clsPtr);
        if (isVaildPtr(realCls)) {
            for (int i = 0; i < NUM_STATIC_OFFSETS; i++) {
                int off = STATIC_CLASS_OFFSETS[i];
                uint64_t staticFields = ReadAddr<uint64_t>(realCls + off);
                if (!isVaildPtr(staticFields)) continue;
                uint64_t match = ReadAddr<uint64_t>(staticFields + OFFSET_CurrentMatch);
                if (isValidMatch(match)) {
                    ESPLog("[GL] Method5 OK (off=0x%X): Match=0x%llX", off, match);
                    return match;
                }
            }
        }
    }

    // --- Method 6: initAddr -> pointer -> GameManager -> Match ---
    uint64_t p1 = ReadAddr<uint64_t>(initAddr);
    if (isVaildPtr(p1)) {
        uint64_t p2 = ReadAddr<uint64_t>(p1);
        if (isVaildPtr(p2)) {
            uint64_t match = ReadAddr<uint64_t>(p2 + OFFSET_CurrentMatch);
            if (isValidMatch(match)) {
                ESPLog("[GL] Method6 OK: Match=0x%llX", match);
                return match;
            }
        }
    }

    // --- Method 7: Brute-force around InitBase (aligned 8-byte steps) ---
    ESPLog("[GL] Method7: Brute-force around InitBase...");
    uint64_t result = 0;
    for (int i = -64; i <= 64 && result == 0; i++) {
        uint64_t testAddr = initAddr + i * 8;
        uint64_t testPtr  = ReadAddr<uint64_t>(testAddr);

        if (!isVaildPtr(testPtr)) continue;

        // 7a: testPtr as direct Match
        if (isValidMatch(testPtr)) {
            ESPLog("[GL] Method7a[%d] OK: Match=0x%llX", i, testPtr);
            result = testPtr; break;
        }

        // 7b: testPtr -> Il2CppClass -> statics -> Match
        for (int j = 0; j < NUM_STATIC_OFFSETS; j++) {
            int off = STATIC_CLASS_OFFSETS[j];
            uint64_t staticFields = ReadAddr<uint64_t>(testPtr + off);
            if (!isVaildPtr(staticFields)) continue;
            uint64_t match = ReadAddr<uint64_t>(staticFields + OFFSET_CurrentMatch);
            if (isValidMatch(match)) {
                ESPLog("[GL] Method7b[%d] OK (off=0x%X): Match=0x%llX", i, off, match);
                result = match; break;
            }
        }
        if (result) break;

        // 7c: testPtr -> GameManager -> Match
        uint64_t match = ReadAddr<uint64_t>(testPtr + OFFSET_CurrentMatch);
        if (isValidMatch(match)) {
            ESPLog("[GL] Method7c[%d] OK: Match=0x%llX", i, match);
            result = match; break;
        }
    }

    if (result) {
        ESPLog("[GL] Method7 final: Match=0x%llX", result);
    } else {
        ESPLog("[GL] All methods failed to find Match");
    }
    return result;
}

// ============================================================
// getMatch
// ============================================================
uint64_t getMatch(uint64_t matchGame) {
    if (!isVaildPtr(matchGame)) return 0;
    // If matchGame already passes isValidMatch, use it directly
    if (isValidMatch(matchGame)) return matchGame;
    // Otherwise try reading one more indirection
    uint64_t m = ReadAddr<uint64_t>(matchGame + OFFSET_CurrentMatch);
    return isValidMatch(m) ? m : 0;
}

// ============================================================
// getLocalPlayer  –  return 0 if not spawned yet (don't abort)
// ============================================================
uint64_t getLocalPlayer(uint64_t match) {
    if (!isVaildPtr(match)) return 0;
    uint64_t lp = ReadAddr<uint64_t>(match + OFFSET_LocalPlayer);
    ESPLog("[GL] LocalPlayer = 0x%llX", lp);
    return lp; // 0 is valid (not spawned / spectating)
}

// ============================================================
// Camera
// ============================================================
uint64_t CameraMain(uint64_t matchGame) {
    if (!isVaildPtr(matchGame)) return 0;
    uint64_t followCam = ReadAddr<uint64_t>(matchGame + OFFSET_FollowCamera);
    if (!isVaildPtr(followCam)) return 0;
    uint64_t cam = ReadAddr<uint64_t>(followCam + OFFSET_Camera);
    return isVaildPtr(cam) ? cam : 0;
}

float* GetViewMatrix(uint64_t cameraMain) {
    if (!isVaildPtr(cameraMain)) return nullptr;
    uint64_t matrixAddr = cameraMain + OFFSET_ViewMatrix;
    static float matrix[16];
    if (_read(matrixAddr, matrix, sizeof(float) * 16)) {
        return matrix;
    }
    return nullptr;
}

float getCameraFov(uint64_t camera) {
    if (!isVaildPtr(camera)) return 60.0f;
    return ReadAddr<float>(camera + 0x3C); // typical FOV offset
}

Vector3 getCameraPosition(uint64_t camera) {
    if (!isVaildPtr(camera)) return {0,0,0};
    uint64_t transform = ReadAddr<uint64_t>(camera + OFFSET_MainCameraTransform);
    if (!isVaildPtr(transform)) return {0,0,0};
    return GetTransformPosition(transform);
}

// ============================================================
// getPlayerList  –  support both Dictionary and List layouts
// ============================================================
int getPlayerList(uint64_t match, uint64_t* outPlayers, int maxCount) {
    if (!outPlayers || maxCount <= 0) return 0;
    memset(outPlayers, 0, sizeof(uint64_t) * maxCount);

    if (!isVaildPtr(match)) return 0;

    uint64_t entities = ReadAddr<uint64_t>(match + OFFSET_DictionaryEntities);
    if (!isVaildPtr(entities)) {
        ESPLog("[GL] DictionaryEntities invalid");
        return 0;
    }

    int count = 0;

    // ---- Try as Dictionary<int, Player> or Dictionary<Player, PlayerData> ----
    uint64_t entries = ReadAddr<uint64_t>(entities + 0x18);
    int dictCount    = ReadAddr<int>(entities + 0x20);

    if (isVaildPtr(entries) && dictCount > 0 && dictCount < 1000) {
        ESPLog("[GL] Reading Dictionary, count=%d", dictCount);
        for (int i = 0; i < dictCount && count < maxCount; i++) {
            uint64_t entry = entries + i * 0x18; // Dictionary entry size (hash+next+key+value)

            // Try both key (offset 0x8) and value (offset 0x10)
            uint64_t pKey   = ReadAddr<uint64_t>(entry + 0x8);
            uint64_t pValue = ReadAddr<uint64_t>(entry + 0x10);

            if (isValidPlayer(pKey)) {
                outPlayers[count++] = pKey;
            } else if (isValidPlayer(pValue)) {
                outPlayers[count++] = pValue;
            }
        }
        if (count > 0) return count;
    }

    // ---- Fallback: Try as List<Player> ----
    uint64_t listItems = ReadAddr<uint64_t>(entities + 0x10);
    int listSize       = ReadAddr<int>(entities + 0x18);

    if (isVaildPtr(listItems) && listSize > 0 && listSize < 1000) {
        ESPLog("[GL] Reading List, size=%d", listSize);
        for (int i = 0; i < listSize && count < maxCount; i++) {
            uint64_t player = ReadAddr<uint64_t>(listItems + i * 8);
            if (isValidPlayer(player)) {
                outPlayers[count++] = player;
            }
        }
    }

    return count;
}

// ============================================================
// Player helpers
// ============================================================
uint64_t getHeadTransform(uint64_t player) {
    if (!isVaildPtr(player)) return 0;
    uint64_t shadow = ReadAddr<uint64_t>(player + OFFSET_Player_ShadowBase);
    if (!isVaildPtr(shadow)) return 0;
    uint64_t xpose = ReadAddr<uint64_t>(shadow + OFFSET_XPose);
    if (!isVaildPtr(xpose)) return 0;
    return ReadAddr<uint64_t>(xpose + 0x30); // head bone typically at +0x30
}

uint64_t getToeTransform(uint64_t player) {
    if (!isVaildPtr(player)) return 0;
    uint64_t shadow = ReadAddr<uint64_t>(player + OFFSET_Player_ShadowBase);
    if (!isVaildPtr(shadow)) return 0;
    uint64_t xpose = ReadAddr<uint64_t>(shadow + OFFSET_XPose);
    if (!isVaildPtr(xpose)) return 0;
    return ReadAddr<uint64_t>(xpose + 0x60); // toe bone typically at +0x60
}

uint32_t getTeamID(uint64_t player) {
    if (!isVaildPtr(player)) return 0;
    return ReadAddr<uint32_t>(player + OFFSET_TeamID);
}

bool isLocalTeamMate(uint64_t localPlayer, uint64_t player) {
    if (localPlayer == 0 || player == 0) return false;
    if (!isVaildPtr(localPlayer) || !isVaildPtr(player)) return false;
    return getTeamID(localPlayer) == getTeamID(player);
}

NSString* getPlayerName(uint64_t player) {
    if (!isVaildPtr(player)) return @"Unknown";
    uint64_t namePtr = ReadAddr<uint64_t>(player + OFFSET_Player_Name);
    if (!isVaildPtr(namePtr)) return @"Bot";

    char buf[64] = {0};
    _read(namePtr, buf, sizeof(buf) - 1);
    buf[63] = 0;

    if (buf[0] == 0) return @"Bot";
    return [NSString stringWithUTF8String:buf];
}

int get_CurHP(uint64_t player) {
    if (!isVaildPtr(player)) return 0;
    uint64_t attr = ReadAddr<uint64_t>(player + OFFSET_PlayerAttributes);
    if (!isVaildPtr(attr)) return 100;
    return ReadAddr<int>(attr + 0x20); // typical curHP offset
}

int get_MaxHP(uint64_t player) {
    if (!isVaildPtr(player)) return 100;
    uint64_t attr = ReadAddr<uint64_t>(player + OFFSET_PlayerAttributes);
    if (!isVaildPtr(attr)) return 100;
    return ReadAddr<int>(attr + 0x24); // typical maxHP offset
}

Vector3 GetTransformPosition(uint64_t transform) {
    Vector3 pos = {0, 0, 0};
    if (!isVaildPtr(transform)) return pos;

    uint64_t posAddr = ReadAddr<uint64_t>(transform + 0x30); // m_Position
    if (isVaildPtr(posAddr)) {
        _read(posAddr + 0x10, &pos, sizeof(Vector3));
    }
    return pos;
}

Vector3 getPositionExt(uint64_t transform) {
    return GetTransformPosition(transform);
}
