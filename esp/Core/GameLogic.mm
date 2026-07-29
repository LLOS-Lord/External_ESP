#import "GameLogic.h"

float* GetViewMatrix(uint64_t cameraMain) {
    if (!isVaildPtr(cameraMain)) return nullptr;
    uint64_t matrix = ReadAddr<uint64_t>(cameraMain + 0x30);
    if (!isVaildPtr(matrix)) return nullptr;
    uint64_t matrix2 = ReadAddr<uint64_t>(matrix + 0x18);
    if (!isVaildPtr(matrix2)) return nullptr;
    static float matrixV[16];
    _read(matrix2 + 0x10, matrixV, sizeof(float) * 16);
    return matrixV;
}


#pragma mark - Function

uint64_t getMatchGame(uint64_t base) {
    uint64_t GameFacade_TypeInfo = ReadAddr<uint64_t>(base + 0x9985B70);
    if (!isVaildPtr(GameFacade_TypeInfo)) {
        NSLog(@"[GL] ERROR: GameFacade_TypeInfo INVALID");
        return 0;
    }
    uint64_t gameFacade = ReadAddr<uint64_t>(GameFacade_TypeInfo + 0xB8);
    if (!isVaildPtr(gameFacade)) {
        NSLog(@"[GL] ERROR: gameFacade INVALID");
        return 0;
    }
    uint64_t matchGame = ReadAddr<uint64_t>(gameFacade + 0x90);
    return matchGame;
}

uint64_t CameraMain(uint64_t matchGame) {
    if (!isVaildPtr(matchGame)) return 0;
    uint64_t CameraControllerManager = ReadAddr<uint64_t>(matchGame + 0xD8);
    if (!isVaildPtr(CameraControllerManager)) return 0;
    // FIX: offset mới +0x20 (cũ +0x18)
    uint64_t CameraMain = ReadAddr<uint64_t>(CameraControllerManager + 0x20);
    return CameraMain;
}

uint64_t getMatch(uint64_t matchGame) {
    if (!isVaildPtr(matchGame)) return 0;
    uint64_t Match = ReadAddr<uint64_t>(matchGame + 0x90);
    return Match;
}

uint64_t getLocalPlayer(uint64_t match) {
    if (!isVaildPtr(match)) return 0;
    // FIX: offset mới +0xD8 (cũ +0x58)
    uint64_t LocalPlayer = ReadAddr<uint64_t>(match + 0xD8);
    return LocalPlayer;
}

uint64_t getHead(uint64_t player) {
    if (!isVaildPtr(player)) return 0;
    // FIX: Head field đã bị xóa. Dùng ITransformNode Array.
    // Thử Transform* duy nhất tại Player + 0x698 (OKOLMFJKGEC)
    uint64_t headTransform = ReadAddr<uint64_t>(player + 0x698);
    if (isVaildPtr(headTransform)) {
        return headTransform;
    }
    // Fallback: brute-force array 0x630~0x6C8 (20 pointers)
    for (int i = 0; i < 20; i++) {
        uint64_t ptr = ReadAddr<uint64_t>(player + 0x630 + i * 8);
        if (isVaildPtr(ptr)) {
            return ptr;
        }
    }
    return 0;
}

uint64_t getRightToeNode(uint64_t player) {
    if (!isVaildPtr(player)) return 0;
    // FIX: Toe field đã bị xóa. Dùng ITransformNode Array.
    // Brute-force tìm bone có Y thấp nhất trong array 0x630~0x6C8
    float minY = 999999.0f;
    uint64_t bestToe = 0;
    for (int i = 0; i < 20; i++) {
        uint64_t ptr = ReadAddr<uint64_t>(player + 0x630 + i * 8);
        if (!isVaildPtr(ptr)) continue;
        Vector3 pos = getPositionExt(ptr);
        if (pos.y < minY && pos.y > 0) {
            minY = pos.y;
            bestToe = ptr;
        }
    }
    return bestToe;
}

bool isLocalTeamMate(uint64_t localPlayer, uint64_t player) {
    if (!isVaildPtr(localPlayer) || !isVaildPtr(player)) return false;
    // FIX: TeamID offset mới Player + 0x3A0 → struct + 0x8
    uint64_t localTeamStruct = ReadAddr<uint64_t>(localPlayer + 0x3A0);
    uint64_t playerTeamStruct = ReadAddr<uint64_t>(player + 0x3A0);
    if (!isVaildPtr(localTeamStruct) || !isVaildPtr(playerTeamStruct)) return false;
    uint8_t localTeamID = ReadAddr<uint8_t>(localTeamStruct + 0x8);
    uint8_t playerTeamID = ReadAddr<uint8_t>(playerTeamStruct + 0x8);
    return localTeamID == playerTeamID;
}

uint16_t GetDataUInt16(uint64_t player) {
    if (!isVaildPtr(player)) return 0;
    // FIX: offset mới +0x78 (cũ +0x68)
    uint64_t IPRIDataPool = ReadAddr<uint64_t>(player + 0x78);
    if (!isVaildPtr(IPRIDataPool)) return 0;
    uint16_t data = ReadAddr<uint16_t>(IPRIDataPool + 0x48);
    return data;
}

int get_CurHP(uint64_t player) {
    uint16_t data = GetDataUInt16(player);
    return (data >> 8) & 0xFF;
}

int get_MaxHP(uint64_t player) {
    uint16_t data = GetDataUInt16(player);
    return data & 0xFF;
}
