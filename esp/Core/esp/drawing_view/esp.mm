#import "esp.h"
#import "../Core/Logger.h"
#import "../Core/ESPData.h"
#include "../Core/GameLogic.h"
#include <cmath>

#define sWidth  [UIScreen mainScreen].bounds.size.width
#define sHeight [UIScreen mainScreen].bounds.size.height

@interface ESP_View ()
@property (nonatomic, strong) NSMutableArray<CALayer *> *layers;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, strong) CADisplayLink *displayLinkDATA;
@property (nonatomic, strong) NSArray<NSValue *> *boxesData;
@end

uint64_t Moudule_Base = -1;

static inline float distanceVec3(Vector3 a, Vector3 b) {
    float dx = a.x - b.x;
    float dy = a.y - b.y;
    float dz = a.z - b.z;
    return sqrtf(dx*dx + dy*dy + dz*dz);
}

@implementation ESP_View

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.layers = [NSMutableArray array];
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        g_playerList = [NSMutableArray array];
        ESPLog("[ESP] View init");

        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            Moudule_Base = (uint64_t)GetGameModule_Base((char*)"Free Fire");
            ESPLog("[ESP] Module Base = 0x%llX", Moudule_Base);
        });

        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateBoxes)];
        [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

        self.displayLinkDATA = [CADisplayLink displayLinkWithTarget:self selector:@selector(update_data)];
        [self.displayLinkDATA addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.superview) {
        self.frame = self.superview.bounds;
    }
    [self updateBoxes];
}

- (void)setBoxes:(NSArray<NSValue *> *)boxes {
    self.boxesData = boxes;
    [self updateBoxes];
}

- (void)updateBoxes {
    for (CALayer *layer in self.layers) {
        [layer removeFromSuperlayer];
    }
    [self.layers removeAllObjects];

    for (PlayerData *data in g_playerList) {
        if (data.distance > 500.0f) continue;

        float boxHeight = fabs(data.screenHead.y - data.screenToe.y);
        float boxWidth = boxHeight * 0.6f;
        float x = data.screenHead.x - boxWidth / 2;
        float y = data.screenHead.y;

        UIColor *color = data.isTeammate ? [UIColor greenColor] : [UIColor redColor];

        CAShapeLayer *boxLayer = [CAShapeLayer layer];
        boxLayer.frame = CGRectMake(x, y, boxWidth, boxHeight);
        boxLayer.borderColor = color.CGColor;
        boxLayer.borderWidth = 2.0f;
        boxLayer.backgroundColor = [UIColor clearColor].CGColor;
        [self.layer addSublayer:boxLayer];
        [self.layers addObject:boxLayer];

        float barWidth = boxWidth;
        float barHeight = 4.0f;
        float barY = y - barHeight - 2;

        CALayer *hpBg = [CALayer layer];
        hpBg.frame = CGRectMake(x, barY, barWidth, barHeight);
        hpBg.backgroundColor = [UIColor darkGrayColor].CGColor;
        [self.layer addSublayer:hpBg];
        [self.layers addObject:hpBg];

        float hpPercent = (float)data.curHP / (float)(data.maxHP > 0 ? data.maxHP : 100);
        CALayer *hpFill = [CALayer layer];
        hpFill.frame = CGRectMake(x, barY, barWidth * hpPercent, barHeight);
        hpFill.backgroundColor = color.CGColor;
        [self.layer addSublayer:hpFill];
        [self.layers addObject:hpFill];

        CATextLayer *nameLayer = [CATextLayer layer];
        nameLayer.string = [NSString stringWithFormat:@"%@ [%.0fm]", data.nickName, data.distance];
        nameLayer.fontSize = 10;
        nameLayer.foregroundColor = [UIColor whiteColor].CGColor;
        nameLayer.frame = CGRectMake(x, barY - 14, 200, 14);
        [self.layer addSublayer:nameLayer];
        [self.layers addObject:nameLayer];
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
    // localPlayer == 0 is OK (not spawned yet / spectating)
    ESPLog("[ESP] localPlayer = 0x%llX (%s)", localPlayer, localPlayer ? "OK" : "NOT SPAWNED");

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
        if (player == localPlayer) continue;

        uint64_t head = getHeadTransform(player);
        uint64_t toe = getToeTransform(player);

        if (!isVaildPtr(head)) {
            ESPLog("[ESP] Player %d: head INVALID", i);
            continue;
        }

        Vector3 headPos = getPositionExt(head);
        Vector3 toePos = isVaildPtr(toe) ? getPositionExt(toe) : headPos;

        ESPLog("[ESP] Player %d: headPos=(%.1f,%.1f,%.1f)", i, headPos.x, headPos.y, headPos.z);

        Vector3 screenHead = WorldToScreen(headPos, matrix, sWidth, sHeight);
        Vector3 screenToe = WorldToScreen(toePos, matrix, sWidth, sHeight);

        if (screenHead.x < 0 || screenHead.x > sWidth || screenHead.y < 0 || screenHead.y > sHeight) {
            if (screenToe.x < 0 || screenToe.x > sWidth || screenToe.y < 0 || screenToe.y > sHeight) {
                continue;
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
        // Only check teammate if localPlayer is valid
        data.isTeammate = (localPlayer != 0) ? isLocalTeamMate(localPlayer, player) : false;
        data.nickName = getPlayerName(player);

        ESPLog("[ESP] Player %d: HP=%d/%d Team=%d Name=%@ Dist=%.1f",
               i, data.curHP, data.maxHP, getTeamID(player), data.nickName, dist);

        [g_playerList addObject:data];
    }

    ESPLog("[ESP] Rendered %d players", (int)g_playerList.count);
}

@end
