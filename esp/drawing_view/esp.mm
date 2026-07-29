#import "esp.h"
#import "Logger.h"

#define sWidth  [UIScreen mainScreen].bounds.size.width
#define sHeight [UIScreen mainScreen].bounds.size.height

@interface ESP_View ()
@property (nonatomic, strong) NSMutableArray<CALayer *> *layers;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, strong) CADisplayLink *displayLinkDATA;
@property (nonatomic, strong) NSArray<NSValue *> *boxesData;
@end

uint64_t Moudule_Base = -1;

@implementation ESP_View

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.layers = [NSMutableArray array];
        self.backgroundColor = [UIColor clearColor];
        ESPLog("[ESP] View init");

        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            Moudule_Base = (uint64_t)GetGameModule_Base((char*)"freefireth");
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

- (void)setBoxes:(NSArray<NSValue *> *)boxes
{
    _boxesData = [boxes copy];
    [self updateBoxes];
}

- (void)updateBoxes {
    if (!self.window) return;
    NSUInteger count = self.boxesData.count;

    if (count == 0)
    {
        for (CALayer *layer in self.layers) { [layer removeFromSuperlayer]; }
        [self.layers removeAllObjects];
        return;
    }

    while (self.layers.count < count)
    {
        CALayer *layer = [CALayer layer];
        layer.borderColor = [UIColor colorWithRed:1 green:0 blue:0 alpha:0.8].CGColor;
        layer.borderWidth = 2.0;
        layer.cornerRadius = 3.0;
        [self.layer addSublayer:layer];
        [self.layers addObject:layer];
    }

    for (NSUInteger i = 0; i < self.layers.count; i++)
    {
        CALayer *layer = self.layers[i];
        if (i < count)
        {
            ESPBox box;
            [self.boxesData[i] getValue:&box];
            layer.hidden = NO;
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            layer.frame = CGRectMake(box.pos.x, box.pos.y, box.width, box.height);
            [CATransaction commit];
        } else {
            layer.hidden = YES;
        }
    }
}

- (void)dealloc {
    ESPLog("[ESP] View dealloc");
    [self.displayLink invalidate];
    [self.displayLinkDATA invalidate];
    self.displayLink = nil;
    self.displayLinkDATA = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)update_data
{
    ESPLog("[ESP] ===== update_data START =====");

    if (Moudule_Base == -1) {
        ESPLog("[ESP] Module_Base = -1, aborting");
        return;
    }

    uint64_t matchGame = getMatchGame(Moudule_Base);
    if (!isVaildPtr(matchGame)) {
        ESPLog("[ESP] matchGame INVALID, aborting");
        return;
    }

    uint64_t camera = CameraMain(matchGame);
    if (!isVaildPtr(camera)) {
        ESPLog("[ESP] Camera INVALID, aborting");
        return;
    }

    uint64_t match = getMatch(matchGame);
    if (!isVaildPtr(match)) {
        ESPLog("[ESP] match INVALID, aborting");
        return;
    }

    uint64_t myPawnObject = getLocalPlayer(match);
    if (!isVaildPtr(myPawnObject)) {
        ESPLog("[ESP] LocalPlayer INVALID, aborting");
        return;
    }

    uint64_t mainCameraTransform = ReadAddr<uint64_t>(myPawnObject + 0x2B0);
    ESPLog("[ESP] mainCameraTransform = 0x%llX", mainCameraTransform);

    Vector3 myLocation = getPositionExt(mainCameraTransform);
    ESPLog("[ESP] MyLocation = (%.2f, %.2f, %.2f)", myLocation.x, myLocation.y, myLocation.z);

    uint64_t player = ReadAddr<uint64_t>(match + 0x158);
    ESPLog("[ESP] Player list ptr (+0x158) = 0x%llX", player);

    if (!isVaildPtr(player)) {
        ESPLog("[ESP] Player list INVALID, trying old offset +0xC8");
        player = ReadAddr<uint64_t>(match + 0xC8);
        ESPLog("[ESP] Fallback Player list = 0x%llX", player);
        if (!isVaildPtr(player)) {
            ESPLog("[ESP] Both offsets failed, aborting");
            return;
        }
    }

    uint64_t tValue = ReadAddr<uint64_t>(player + 0x28);
    ESPLog("[ESP] tValue = 0x%llX", tValue);

    if (!isVaildPtr(tValue)) {
        ESPLog("[ESP] tValue INVALID, aborting");
        return;
    }

    int coutValue = ReadAddr<int>(tValue + 0x18);
    ESPLog("[ESP] Player count = %d", coutValue);

    if (coutValue <= 0 || coutValue > 100) {
        ESPLog("[ESP] Player count suspicious (%d), aborting", coutValue);
        return;
    }

    float *matrix = GetViewMatrix(camera);

    NSMutableArray<NSValue *> *boxesMutable = [NSMutableArray array];
    int countObject = 0;

    for (int i = 0; i < coutValue; i++) {
        uint64_t PawnObject = ReadAddr<uint64_t>(tValue + 0x20 + 8 * i);
        ESPLog("[ESP] Player[%d] ptr = 0x%llX", i, PawnObject);

        if (!isVaildPtr(PawnObject)) {
            ESPLog("[ESP] Player[%d] invalid pointer", i);
            continue;
        }

        bool isLocalTeam = isLocalTeamMate(myPawnObject, PawnObject);
        if (isLocalTeam) {
            ESPLog("[ESP] Player[%d] is teammate, skip", i);
            continue;
        }

        NSString *Name = GetNickName(PawnObject);
        ESPLog("[ESP] Player[%d] name = '%s'", i, [Name UTF8String]);

        int CurHP = get_CurHP(PawnObject);
        int MaxHP = get_MaxHP(PawnObject);
        ESPLog("[ESP] Player[%d] HP = %d/%d", i, CurHP, MaxHP);

        uint64_t headPtr = getHead(PawnObject);
        uint64_t toePtr = getRightToeNode(PawnObject);

        if (!isVaildPtr(headPtr) || !isVaildPtr(toePtr)) {
            ESPLog("[ESP] Player[%d] head(0x%llX) or toe(0x%llX) invalid, skip", i, headPtr, toePtr);
            continue;
        }

        Vector3 HeadLocation = getPositionExt(headPtr);
        HeadLocation.y += 0.2f;

        Vector3 RightToePos = getPositionExt(toePtr);

        ESPLog("[ESP] Player[%d] Head=(%.2f,%.2f,%.2f) Toe=(%.2f,%.2f,%.2f)", 
              i, HeadLocation.x, HeadLocation.y, HeadLocation.z,
              RightToePos.x, RightToePos.y, RightToePos.z);

        Vector3 w2sHeadLocation = WorldToScreen(HeadLocation, matrix, sWidth, sHeight);
        Vector3 w2sRightToePos = WorldToScreen(RightToePos, matrix, sWidth, sHeight);

        ESPLog("[ESP] Player[%d] W2S Head=(%.1f,%.1f) Toe=(%.1f,%.1f)",
              i, w2sHeadLocation.x, w2sHeadLocation.y, w2sRightToePos.x, w2sRightToePos.y);

        float dis = Vector3::Distance(myLocation, HeadLocation);
        ESPLog("[ESP] Player[%d] distance = %.1f", i, dis);

        if (dis > 220.0f) {
            ESPLog("[ESP] Player[%d] too far, skip", i);
            continue;
        }

        countObject++;

        float boxHeight = abs(w2sHeadLocation.y - w2sRightToePos.y);
        float boxWidth = boxHeight * 0.5f;
        float x = w2sHeadLocation.x - boxWidth * 0.5f;
        float y = w2sHeadLocation.y;

        ESPLog("[ESP] Player[%d] BOX x=%.1f y=%.1f w=%.1f h=%.1f", i, x, y, boxWidth, boxHeight);

        ESPBox espBox;
        espBox.pos.x = x;
        espBox.pos.y = y;
        espBox.width = boxWidth;
        espBox.height = boxHeight;

        NSValue *val = [NSValue valueWithBytes:&espBox objCType:@encode(ESPBox)];
        [boxesMutable addObject:val];
    }

    ESPLog("[ESP] ===== Total boxes: %d =====", countObject);

    self.boxes = boxesMutable;
    [self setNeedsDisplay];
}


@end
