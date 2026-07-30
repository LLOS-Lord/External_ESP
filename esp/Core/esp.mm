#import "ESPData.h"
#include "GameLogic.h"
#include "Logger.h"
#include <cmath>

// Simple distance function
static inline float distanceVec3(Vector3 a, Vector3 b) {
    float dx = a.x - b.x;
    float dy = a.y - b.y;
    float dz = a.z - b.z;
    return sqrtf(dx*dx + dy*dy + dz*dz);
}

@implementation ESP_View

- (instancetype)init {
    self = [super init];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        g_playerList = [NSMutableArray array];
        ESPLog("[ESP] View init");
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    if (g_playerList.count == 0) return;

    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextClearRect(context, rect);

    for (PlayerData *data in g_playerList) {
        if (data.distance > 500.0f) continue;

        float boxHeight = fabs(data.screenHead.y - data.screenToe.y);
        float boxWidth = boxHeight * 0.6f;
        float x = data.screenHead.x - boxWidth / 2;
        float y = data.screenHead.y;

        UIColor *color = data.isTeammate ? [UIColor greenColor] : [UIColor redColor];
        CGContextSetStrokeColorWithColor(context, color.CGColor);
        CGContextSetLineWidth(context, 2.0f);
        CGContextStrokeRect(context, CGRectMake(x, y, boxWidth, boxHeight));

        // HP Bar
        float hpPercent = (float)data.curHP / (float)(data.maxHP > 0 ? data.maxHP : 100);
        float barWidth = boxWidth;
        float barHeight = 4.0f;
        float barY = y - barHeight - 2;

        CGContextSetFillColorWithColor(context, [UIColor darkGrayColor].CGColor);
        CGContextFillRect(context, CGRectMake(x, barY, barWidth, barHeight));

        CGContextSetFillColorWithColor(context, data.isTeammate ? [UIColor greenColor].CGColor : [UIColor redColor].CGColor);
        CGContextFillRect(context, CGRectMake(x, barY, barWidth * hpPercent, barHeight));

        // Name & Distance
        NSString *info = [NSString stringWithFormat:@"%@ [%.0fm]", data.nickName, data.distance];
        NSDictionary *attrs = @{
            NSFontAttributeName: [UIFont systemFontOfSize:10],
            NSForegroundColorAttributeName: [UIColor whiteColor]
        };
        [info drawAtPoint:CGPointMake(x, barY - 14) withAttributes:attrs];
    }
}

- (void)update_data {
    ESPLog("[ESP] ===== update_data START =====");

    uint64_t base = GetGameModule_Base((char*)"Free Fire");
    if (base == 0) {
        ESPLog("[ESP] Module Base = 0, aborting");
        return;
    }
    ESPLog("[ESP] Module Base = 0x%llX", base);

    uint64_t matchGame = getMatchGame(base);
    if (!isVaildPtr(matchGame)) {
        ESPLog("[ESP] matchGame INVALID, aborting");
        return;
    }
    ESPLog("[ESP] matchGame = 0x%llX", matchGame);

    uint64_t match = getMatch(matchGame);
    if (!isVaildPtr(match)) {
        ESPLog("[ESP] match INVALID");
        return;
    }
    ESPLog("[ESP] match = 0x%llX", match);

    uint64_t localPlayer = getLocalPlayer(match);
    if (!isVaildPtr(localPlayer)) {
        ESPLog("[ESP] localPlayer INVALID");
        return;
    }
    ESPLog("[ESP] localPlayer = 0x%llX", localPlayer);

    uint64_t camera = CameraMain(matchGame);
    if (!isVaildPtr(camera)) {
        ESPLog("[ESP] camera INVALID");
        return;
    }
    ESPLog("[ESP] camera = 0x%llX", camera);

    float* matrix = GetViewMatrix(camera);
    if (!matrix) {
        ESPLog("[ESP] matrix NULL");
        return;
    }
    ESPLog("[ESP] matrix OK");

    memcpy(g_matrix, matrix, sizeof(float) * 16);
    g_cameraFov = getCameraFov(camera);
    g_cameraPos = getCameraPosition(camera);

    ESPLog("[ESP] FOV=%.1f Pos=(%.1f,%.1f,%.1f)", g_cameraFov, g_cameraPos.x, g_cameraPos.y, g_cameraPos.z);

    // Read player list
    uint64_t players[100];
    int playerCount = getPlayerList(match, players, 100);

    if (playerCount == 0) {
        ESPLog("[ESP] No players found");
        return;
    }

    ESPLog("[ESP] Found %d players", playerCount);

    [g_playerList removeAllObjects];

    for (int i = 0; i < playerCount; i++) {
        uint64_t player = players[i];
        if (!isVaildPtr(player)) continue;
        if (player == localPlayer) continue; // Skip self

        uint64_t head = getHeadTransform(player);
        uint64_t toe = getToeTransform(player);

        if (!isVaildPtr(head)) {
            ESPLog("[ESP] Player %d: head INVALID", i);
            continue;
        }

        Vector3 headPos = GetTransformPosition(head);
        Vector3 toePos = isVaildPtr(toe) ? GetTransformPosition(toe) : headPos;

        ESPLog("[ESP] Player %d: headPos=(%.1f,%.1f,%.1f)", i, headPos.x, headPos.y, headPos.z);

        // FIX: WorldToScreen signature: (Vector3, float*, float, float) -> Vector3
        Vector3 screenHead = WorldToScreen(headPos, matrix, screenWidth, screenHeight);
        Vector3 screenToe = WorldToScreen(toePos, matrix, screenWidth, screenHeight);

        // Check if on screen
        if (screenHead.x < 0 || screenHead.x > screenWidth || screenHead.y < 0 || screenHead.y > screenHeight) {
            if (screenToe.x < 0 || screenToe.x > screenWidth || screenToe.y < 0 || screenToe.y > screenHeight) {
                continue; // Both off screen
            }
        }

        float dist = distanceVec3(g_cameraPos, headPos);

        PlayerData *data = [[PlayerData alloc] init];
        data.screenHead = screenHead;
        data.screenToe = screenToe;
        data.boxHeight = fabs(screenHead.y - screenToe.y);
        data.boxWidth = data.boxHeight * 0.6f;
        data.curHP = get_CurHP(player);
        data.maxHP = get_MaxHP(player);
        data.distance = dist;
        data.isTeammate = isLocalTeamMate(localPlayer, player);
        data.nickName = getPlayerName(player);

        ESPLog("[ESP] Player %d: HP=%d/%d Team=%d Name=%@ Dist=%.1f", 
               i, data.curHP, data.maxHP, getTeamID(player), data.nickName, dist);

        [g_playerList addObject:data];
    }

    ESPLog("[ESP] Rendered %d players", (int)g_playerList.count);
    [self setNeedsDisplay];
}

@end
