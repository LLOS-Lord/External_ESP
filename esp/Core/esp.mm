#import "esp.h"

#pragma mark - Function

void update_data() {
    if (Moudule_Base == 0) {
        //NSLog(@"[ESP] Module Base = 0x0");
        return;
    }
    //NSLog(@"[ESP] ===== update_data START =====");

    uint64_t matchGame = getMatchGame(Moudule_Base);
    if (!isVaildPtr(matchGame)) {
        //NSLog(@"[ESP] matchGame INVALID, aborting");
        return;
    }

    uint64_t match = getMatch(matchGame);
    if (!isVaildPtr(match)) {
        //NSLog(@"[ESP] match INVALID");
        return;
    }

    uint64_t cameraMain = CameraMain(matchGame);
    if (!isVaildPtr(cameraMain)) {
        //NSLog(@"[ESP] cameraMain INVALID");
        return;
    }

    // FIX: Player List offset mới +0x158 (cũ +0xC8)
    uint64_t players = ReadAddr<uint64_t>(match + 0x158);
    if (!isVaildPtr(players)) {
        //NSLog(@"[ESP] players list INVALID");
        return;
    }

    int playerCount = ReadAddr<int>(match + 0x160);
    if (playerCount <= 0 || playerCount > 100) {
        return;
    }

    uint64_t myPawnObject = getLocalPlayer(match);
    if (!isVaildPtr(myPawnObject)) {
        //NSLog(@"[ESP] myPawnObject INVALID");
        return;
    }

    uint64_t mainCameraTransform = ReadAddr<uint64_t>(myPawnObject + 0x2B0);

    uint64_t matrix = ReadAddr<uint64_t>(cameraMain + 0x30);
    uint64_t matrix2 = ReadAddr<uint64_t>(matrix + 0x18);
    float matrixV[16];
    _read(matrix2 + 0x10, matrixV, sizeof(float) * 16);

    float cameraFov = ReadAddr<float>(cameraMain + 0x48);

    Vector3 cameraPos = getPositionExt(mainCameraTransform);

    g_cameraFov = cameraFov;
    g_cameraPos = cameraPos;
    g_matrix = matrixV;

    [g_playerList removeAllObjects];

    for (int i = 0; i < playerCount; i++) {
        uint64_t player = ReadAddr<uint64_t>(players + (i * 0x8));
        if (!isVaildPtr(player)) continue;

        uint64_t IPRIDataPool = ReadAddr<uint64_t>(player + 0x78);
        if (!isVaildPtr(IPRIDataPool)) continue;

        uint64_t playerController = ReadAddr<uint64_t>(player + 0x30);
        if (!isVaildPtr(playerController)) continue;

        uint64_t pawnObject = ReadAddr<uint64_t>(playerController + 0x28);
        if (!isVaildPtr(pawnObject)) continue;

        uint64_t head = getHead(pawnObject);
        uint64_t toe = getRightToeNode(pawnObject);

        if (!isVaildPtr(head) || !isVaildPtr(toe)) continue;

        Vector3 headPos = getPositionExt(head);
        Vector3 toePos = getPositionExt(toe);

        if (headPos.x == 0 && headPos.y == 0 && headPos.z == 0) continue;
        if (toePos.x == 0 && toePos.y == 0 && toePos.z == 0) continue;

        Vector3 screenHead = WorldToScreen(headPos, matrixV, screenWidth, screenHeight);
        Vector3 screenToe = WorldToScreen(toePos, matrixV, screenWidth, screenHeight);

        if (screenHead.z < 0 || screenToe.z < 0) continue;

        int curHP = get_CurHP(pawnObject);
        int maxHP = get_MaxHP(pawnObject);
        if (curHP <= 0 || curHP > 255) continue;

        NSString *nickName = GetNickName(pawnObject);
        if (!nickName || nickName.length == 0) nickName = @"???";

        bool isTeammate = isLocalTeamMate(myPawnObject, pawnObject);

        float distance = sqrt(
            pow(cameraPos.x - headPos.x, 2) +
            pow(cameraPos.y - headPos.y, 2) +
            pow(cameraPos.z - headPos.z, 2)
        );

        float boxHeight = fabs(screenHead.y - screenToe.y);
        float boxWidth = boxHeight * 0.6f;

        PlayerData *data = [[PlayerData alloc] init];
        data->screenHead = screenHead;
        data->screenToe = screenToe;
        data->boxHeight = boxHeight;
        data->boxWidth = boxWidth;
        data->curHP = curHP;
        data->maxHP = maxHP;
        data->distance = distance;
        data->isTeammate = isTeammate;
        data->nickName = nickName;

        [g_playerList addObject:data];
    }
}
