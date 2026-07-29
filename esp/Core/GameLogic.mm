#import "GameLogic.h"

#pragma mark - Function Game

uint64_t getMatchGame(uint64_t Moudule_Base) {
    uint64_t GameFacade_TypeInfo = ReadAddr<uint64_t>(Moudule_Base + 0x9985B70);
    NSLog(@"[DEBUG] GameFacade_TypeInfo = 0x%llX", GameFacade_TypeInfo);

    if (!isVaildPtr(GameFacade_TypeInfo)) {
        NSLog(@"[DEBUG] ERROR: GameFacade_TypeInfo invalid!");
        return 0;
    }

    uint64_t GameFacade_Static = ReadAddr<uint64_t>(GameFacade_TypeInfo + 0xB8);
    NSLog(@"[DEBUG] GameFacade_Static = 0x%llX", GameFacade_Static);

    uint64_t matchGame = ReadAddr<uint64_t>(GameFacade_Static + 0x0);
    NSLog(@"[DEBUG] matchGame = 0x%llX", matchGame);
    return matchGame;
}

uint64_t getMatch(uint64_t matchgame) {
    uint64_t match = ReadAddr<uint64_t>(matchgame + 0x90);
    NSLog(@"[DEBUG] getMatch = 0x%llX", match);
    return match;
}

uint64_t CameraMain(uint64_t matchgame) {
    uint64_t CameraControllerManager = ReadAddr<uint64_t>(matchgame + 0xD8);
    NSLog(@"[DEBUG] CameraControllerManager = 0x%llX", CameraControllerManager);

    uint64_t camera = ReadAddr<uint64_t>(CameraControllerManager + 0x20);
    NSLog(@"[DEBUG] CameraMain = 0x%llX", camera);
    return camera;
}

float* GetViewMatrix(uint64_t cameraMain) {
    uint64_t v1 = ReadAddr<uint64_t>(cameraMain + 0x10);
    NSLog(@"[DEBUG] ViewMatrix v1 = 0x%llX", v1);

    static float matrix[16];
    for (int i = 0; i < 16; i++) {
        matrix[i] = ReadAddr<float>(v1 + 0xD8 + i * 0x4);
    }
    NSLog(@"[DEBUG] ViewMatrix[0]=%f [5]=%f [10]=%f [15]=%f", matrix[0], matrix[5], matrix[10], matrix[15]);
    return matrix;
}

uint64_t getTransNode(uint64_t BodyPart) {
    return ReadAddr<uint64_t>(BodyPart + 0x10);
}

// DEBUG: Try multiple head offsets
uint64_t getHead(uint64_t player) {
    // Try +0x698 first (OKOLMFJKGEC - only Transform*)
    uint64_t head = ReadAddr<uint64_t>(player + 0x698);
    NSLog(@"[DEBUG] Head candidate at +0x698 = 0x%llX", head);

    if (!isVaildPtr(head)) {
        // Fallback: try +0x630 (first ITransformNode)
        uint64_t itn = ReadAddr<uint64_t>(player + 0x630);
        head = getTransNode(itn);
        NSLog(@"[DEBUG] Head fallback +0x630 = 0x%llX", head);
    }
    return head;
}

// DEBUG: Try multiple toe offsets
uint64_t getRightToeNode(uint64_t player) {
    // Try +0x630 first
    uint64_t toeITN = ReadAddr<uint64_t>(player + 0x630);
    uint64_t toe = getTransNode(toeITN);
    NSLog(@"[DEBUG] Toe candidate +0x630 -> 0x%llX", toe);

    if (!isVaildPtr(toe)) {
        // Try +0x638
        toeITN = ReadAddr<uint64_t>(player + 0x638);
        toe = getTransNode(toeITN);
        NSLog(@"[DEBUG] Toe fallback +0x638 -> 0x%llX", toe);
    }
    return toe;
}

uint64_t getLocalPlayer(uint64_t match) {
    uint64_t local = ReadAddr<uint64_t>(match + 0xD8);
    NSLog(@"[DEBUG] LocalPlayer = 0x%llX", local);
    return local;
}

bool isLocalTeamMate(uint64_t localPlayer, uint64_t Player) {
    COW_GamePlay_PlayerID_o myPlayerID = ReadAddr<COW_GamePlay_PlayerID_o>(localPlayer + 0x3A8);
    COW_GamePlay_PlayerID_o PlayerID = ReadAddr<COW_GamePlay_PlayerID_o>(Player + 0x3A8);

    int myTeamID = myPlayerID.m_TeamID;
    int TeamID = PlayerID.m_TeamID;

    NSLog(@"[DEBUG] Team check: my=%d vs enemy=%d", myTeamID, TeamID);
    return myTeamID == TeamID;
}

int GetDataUInt16(uint64_t player, int varID) {
    uint64_t IPRIDataPool = ReadAddr<uint64_t>(player + 0x78);
    NSLog(@"[DEBUG] IPRIDataPool = 0x%llX", IPRIDataPool);

    if (isVaildPtr(IPRIDataPool)) {
        uint64_t v2 = ReadAddr<uint64_t>(IPRIDataPool + 0x10);
        uint64_t v4 = ReadAddr<uint64_t>(v2 + 0x8 * varID + 0x20);
        int v6 = ReadAddr<int>(v4 + 0x18);
        NSLog(@"[DEBUG] HP varID=%d -> %d", varID, v6);
        return v6;
    }
    NSLog(@"[DEBUG] IPRIDataPool INVALID!");
    return 0;
}

int get_CurHP(uint64_t Player) {
    return GetDataUInt16(Player, 0);
}

int get_MaxHP(uint64_t Player) {
    return GetDataUInt16(Player, 1);
}
