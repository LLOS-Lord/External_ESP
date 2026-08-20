#include "esp.h"
#include "GameLogic.h"
#include "MemoryUtils.h"
#include "OffsetResolver.h"
#include "Logger.h"
#include "Offsets.h"
#include <pthread.h>
#include <chrono>
#include <cmath>

// ==========================================
// GLOBALS
// ==========================================
static NSMutableArray<PlayerData*>* playerList = nil;
static pthread_mutex_t listMutex = PTHREAD_MUTEX_INITIALIZER;

// ==========================================
// INIT
// ==========================================

void esp_init() {
    playerList = [NSMutableArray array];
    ESPLog("[ESP] Init complete");
}

// ==========================================
// UPDATE DATA
// ==========================================

void update_data() {
    static int attachRetryCount = 0;
    static auto lastAttachAttempt = std::chrono::steady_clock::now();

    if (Module_Base == 0) {
        auto now = std::chrono::steady_clock::now();
        auto elapsed = std::chrono::duration_cast<std::chrono::seconds>(now - lastAttachAttempt).count();

        if (elapsed >= 3 && attachRetryCount < 20) {
            lastAttachAttempt = now;
            attachRetryCount++;

            const char* gameNames[] = {
                "freefireth",
                "freefirethm",
                "freefireth_ob",
                "Free Fire",
                "GarenaFreeFire",
                "freefire",
                "FreeFire",
                nullptr
            };

            for (int i = 0; gameNames[i] != nullptr; i++) {
                char nameBuf[64];
                strncpy(nameBuf, gameNames[i], 63);
                nameBuf[63] = '\0';

                ESPLog("[ESP] Attempting attach to '%s' (try %d/20)...", nameBuf, attachRetryCount);
                uint64_t base = GetGameModule_Base(nameBuf);
                if (base != 0) {
                    ESPLog("[ESP] SUCCESS! Module_Base = 0x%llX (game: %s)", base, nameBuf);
                    Module_Base = base;
                    attachRetryCount = 0;
                    break;
                }
            }

            if (Module_Base == 0) {
                ESPLog("[ESP] Attach failed, retrying in 3s...");
            }
        }
        return;
    }

    ESPLog("[ESP] ===== update_data START =====");

    // Check lobby state
    if (IsAtLobby()) {
        ESPLog("[ESP] In lobby/loading, clearing list");
        pthread_mutex_lock(&listMutex);
        [playerList removeAllObjects];
        pthread_mutex_unlock(&listMutex);
        return;
    }

    // Auto-resolve offsets if needed
    if (!g_resolved.resolved) {
        ESPLog("[ESP] Auto-resolving offsets...");
        if (!resolveOffsets(Module_Base, 256ULL * 1024 * 1024)) {
            ESPLog("[ESP] Offset resolution failed, will retry...");
            return;
        }
    }

    uint64_t match = getMatchGame();
    if (match == 0) {
        ESPLog("[ESP] matchGame = 0, clearing list");
        pthread_mutex_lock(&listMutex);
        [playerList removeAllObjects];
        pthread_mutex_unlock(&listMutex);
        return;
    }

    ESPLog("[GL] getMatchGame: match = 0x%llX", match);

    uint64_t localPlayer = getLocalPlayer(match);
    int localTeam = 0;
    if (localPlayer != 0) {
        localTeam = readU32(localPlayer + OFFSET_TeamID);
        ESPLog("[GL] LocalPlayer: 0x%llX, Team: %d", localPlayer, localTeam);
    }

    std::vector<PlayerInfo> rawList = getPlayerList();
    NSMutableArray<PlayerData*>* tempList = [NSMutableArray array];

    // Get screen dimensions
    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    CGFloat screenH = [UIScreen mainScreen].bounds.size.height;

    // Get view matrix
    float* matrix = GetViewMatrix(0);

    for (const auto& p : rawList) {
        if (p.address == localPlayer) continue;
        if (p.isDead) continue;

        PlayerData* data = [[PlayerData alloc] init];
        data.address  = p.address;
        data.head     = p.head;
        data.toe      = p.toe;
        data.hip      = p.hip;
        data.lHand    = p.lHand;
        data.rHand    = p.rHand;
        data.lElbow   = p.lElbow;
        data.rElbow   = p.rElbow;
        data.lShoulder = p.lShoulder;
        data.rShoulder = p.rShoulder;
        data.lAnkle   = p.lAnkle;
        data.rAnkle   = p.rAnkle;
        data.lToe     = p.lToe;
        data.rToe     = p.rToe;
        data.hp       = static_cast<int>(p.hp);
        data.maxHp    = static_cast<int>(p.maxHp);
        data.team     = static_cast<int>(p.team);
        data.isEnemy  = (p.team != localTeam);
        data.isBot    = p.isBot;
        data.isVisible = p.isVisible;
        data.name     = [NSString stringWithUTF8String:p.name.c_str()];

        // World-to-screen for head and toe
        if (matrix) {
            Vector3 screenHead = WorldToScreen(p.head, matrix, screenW, screenH);
            Vector3 screenToe  = WorldToScreen(p.toe, matrix, screenW, screenH);
            data.screenHead = screenHead;
            data.screenToe  = screenToe;

            // Calculate box dimensions
            if (screenHead.z > 0.01f && screenToe.z > 0.01f) {
                data.boxHeight = fabsf(screenToe.y - screenHead.y);
                data.boxWidth  = data.boxHeight * 0.4f;
            }
        }

        // Legacy fields
        data.curHP    = data.hp;
        data.maxHP    = data.maxHp;
        data.nickName = data.name;
        data.isTeammate = !data.isEnemy;

        [tempList addObject:data];
    }

    pthread_mutex_lock(&listMutex);
    playerList = tempList;
    pthread_mutex_unlock(&listMutex);

    ESPLog("[ESP] Updated %lu players", (unsigned long)tempList.count);
}

// ==========================================
// GET PLAYER LIST
// ==========================================

NSArray<PlayerData*>* getPlayerListData() {
    pthread_mutex_lock(&listMutex);
    NSArray<PlayerData*>* copy = [playerList copy];
    pthread_mutex_unlock(&listMutex);
    return copy;
}

// ==========================================
// ESP_View IMPLEMENTATION
// ==========================================

@implementation ESP_View {
    NSMutableArray<NSValue *> *_boxes;
    CADisplayLink *_displayLink;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        _boxes = [NSMutableArray array];
        esp_init();
        _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
    return self;
}

- (void)dealloc {
    [_displayLink invalidate];
}

- (void)tick:(CADisplayLink *)link {
    update_data();
    [self setNeedsDisplay];
}

- (void)setBoxes:(NSArray<NSValue *> *)boxes {
    _boxes = [boxes mutableCopy];
    [self setNeedsDisplay];
}

- (void)updateBoxes {
    [self setNeedsDisplay];
}

- (void)update_data {
    update_data();
}

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];

    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    NSArray<PlayerData *> *players = getPlayerListData();
    if (!players || players.count == 0) return;

    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;

    for (PlayerData *p in players) {
        // Skip if behind camera
        if (p.screenHead.z < 0.01f || p.screenToe.z < 0.01f) continue;

        // Color based on enemy/teammate
        UIColor* boxColor = p.isEnemy ? [UIColor redColor] : [UIColor greenColor];
        CGContextSetStrokeColorWithColor(ctx, boxColor.CGColor);
        CGContextSetLineWidth(ctx, 2.0);

        // Calculate box rect
        CGFloat boxW = p.boxWidth;
        CGFloat boxH = p.boxHeight;
        CGFloat boxX = p.screenHead.x - boxW * 0.5f;
        CGFloat boxY = p.screenHead.y;

        CGRect box = CGRectMake(boxX, boxY, boxW, boxH);
        CGContextStrokeRect(ctx, box);

        // Draw name
        NSString *label = p.name ?: @"???";
        if (p.isBot) label = [label stringByAppendingString:@" [BOT]"];
        if (!p.isVisible) label = [label stringByAppendingString:@" [HIDDEN]"];

        NSDictionary *attrs = @{
            NSFontAttributeName: [UIFont systemFontOfSize:10],
            NSForegroundColorAttributeName: boxColor
        };
        [label drawAtPoint:CGPointMake(CGRectGetMinX(box), CGRectGetMinY(box) - 14) withAttributes:attrs];

        // Draw HP bar
        CGFloat hpRatio = (p.maxHp > 0) ? (float)p.hp / (float)p.maxHp : 0;
        CGFloat barW = CGRectGetWidth(box);
        CGFloat barH = 4;
        CGFloat barX = CGRectGetMinX(box);
        CGFloat barY = CGRectGetMinY(box) - barH - 2;

        CGContextSetFillColorWithColor(ctx, [UIColor darkGrayColor].CGColor);
        CGContextFillRect(ctx, CGRectMake(barX, barY, barW, barH));

        UIColor* hpColor = (hpRatio > 0.5f ? [UIColor greenColor] : (hpRatio > 0.25f ? [UIColor yellowColor] : [UIColor redColor]));
        CGContextSetFillColorWithColor(ctx, hpColor.CGColor);
        CGContextFillRect(ctx, CGRectMake(barX, barY, barW * hpRatio, barH));

        // Draw skeleton lines (if bones are valid)
        CGContextSetLineWidth(ctx, 1.5);
        UIColor* boneColor = p.isEnemy ? [UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:0.8] : [UIColor colorWithRed:0.3 green:1.0 blue:0.3 alpha:0.8];
        CGContextSetStrokeColorWithColor(ctx, boneColor.CGColor);

        // Helper to draw bone line
        auto drawBone = [&](Vector3 a, Vector3 b) {
            if (a.z < 0.01f || b.z < 0.01f) return;
            CGContextMoveToPoint(ctx, a.x, a.y);
            CGContextAddLineToPoint(ctx, b.x, b.y);
            CGContextStrokePath(ctx);
        };

        // Spine
        drawBone(p.head, p.hip);
        // Arms
        drawBone(p.lShoulder, p.lElbow);
        drawBone(p.lElbow, p.lHand);
        drawBone(p.rShoulder, p.rElbow);
        drawBone(p.rElbow, p.rHand);
        // Legs
        drawBone(p.hip, p.lAnkle);
        drawBone(p.hip, p.rAnkle);
        drawBone(p.lAnkle, p.lToe);
        drawBone(p.rAnkle, p.rToe);
    }
}

@end
