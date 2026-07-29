#import "GameLogic.h"

#pragma mark - Function Game

uint64_t getMatchGame(uint64_t Moudule_Base) {
    uint64_t GameFacade_TypeInfo = ReadAddr<uint64_t>(Moudule_Base + 0x9985B70);
    uint64_t GameFacade_Static = ReadAddr<uint64_t>(GameFacade_TypeInfo + 0xB8);
    return ReadAddr<uint64_t>(GameFacade_Static + 0x0);
}

uint64_t getMatch(uint64_t matchgame) {
    return ReadAddr<uint64_t>(matchgame + 0x90);
}

uint64_t CameraMain(uint64_t matchgame) {
    uint64_t CameraControllerManager = ReadAddr<uint64_t>(matchgame + 0xD8);
    // PATCHED: offset camera pointer changed +0x18 -> +0x20
    return ReadAddr<uint64_t>(CameraControllerManager + 0x20);
}

float* GetViewMatrix(uint64_t cameraMain) {
    uint64_t v1 = ReadAddr<uint64_t>(cameraMain + 0x10);

    static float matrix[16];
    for (int i = 0; i < 16; i++) {
        matrix[i] = ReadAddr<float>(v1 + 0xD8 + i * 0x4);
    }

    return matrix;
}

uint64_t getTransNode(uint64_t BodyPart) {
    return ReadAddr<uint64_t>(BodyPart + 0x10);
}

// PATCHED: Head field removed in new dump. Using OKOLMFJKGEC at +0x698 (Transform*)
// NOTE: This is the ONLY Transform* in the ITransformNode array (0x630~0x6C8)
// If ESP box is misaligned, try other offsets in the array or hook GetHeadTF()
uint64_t getHead(uint64_t player) {
    // Direct Transform* pointer at +0x698
    return ReadAddr<uint64_t>(player + 0x698);
}

// PATCHED: Toe field removed in new dump. Using first ITransformNode at +0x630
// NOTE: This is a GUESS. If wrong, try offsets: 0x638, 0x640, 0x648... up to 0x6C8
// Or hook GetLeftToeTF() / GetRightToeTF() to find correct offset
uint64_t getRightToeNode(uint64_t player) {
    uint64_t iTransformNode = ReadAddr<uint64_t>(player + 0x630);
    return getTransNode(iTransformNode);
}

// PATCHED: Local Player offset changed +0x58 -> +0xD8
uint64_t getLocalPlayer(uint64_t match) {
    return ReadAddr<uint64_t>(match + 0xD8);
}

// PATCHED: TeamID offset changed +0x2D0 -> +0x3A8 (struct at +0x3A0, TeamID at +0x8)
bool isLocalTeamMate(uint64_t localPlayer, uint64_t Player) {
    COW_GamePlay_PlayerID_o myPlayerID = ReadAddr<COW_GamePlay_PlayerID_o>(localPlayer + 0x3A8);
    COW_GamePlay_PlayerID_o PlayerID = ReadAddr<COW_GamePlay_PlayerID_o>(Player + 0x3A8);

    int myTeamID = myPlayerID.m_TeamID;
    int TeamID = PlayerID.m_TeamID;

    return myTeamID == TeamID;
}

// PATCHED: IPRIDataPool offset changed +0x68 -> +0x78
int GetDataUInt16(uint64_t player, int varID) {
    uint64_t IPRIDataPool = ReadAddr<uint64_t>(player + 0x78);
    if (isVaildPtr(IPRIDataPool)) {
        uint64_t v2 = ReadAddr<uint64_t>(IPRIDataPool + 0x10);
        uint64_t v4 = ReadAddr<uint64_t>(v2 + 0x8 * varID + 0x20);
        int v6 = ReadAddr<int>(v4 + 0x18);
        return v6;
    }
    return 0;
}

int get_CurHP(uint64_t Player) {
    return GetDataUInt16(Player, 0);
}

int get_MaxHP(uint64_t Player) {
    return GetDataUInt16(Player, 1);
}
