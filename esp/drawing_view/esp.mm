#import "esp.h"

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

        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            Moudule_Base = (uint64_t)GetGameModule_Base((char*)"freefireth");
            NSLog(@"[DEBUG] Module Base = 0x%llX", Moudule_Base);
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
    [self.displayLink invalidate];
    [self.displayLinkDATA invalidate];
    self.displayLink = nil;
    self.displayLinkDATA = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)update_data
{
    if (Moudule_Base == -1) {
        NSLog(@"[DEBUG] Module_Base = -1, aborting");
        return;
    }

    uint64_t matchGame = getMatchGame(Moudule_Base);
    if (!isVaildPtr(matchGame)) {
        NSLog(@"[DEBUG] matchGame INVALID, aborting");
        return;
    }

    uint64_t camera = CameraMain(matchGame);
    if (!isVaildPtr(camera)) {
        NSLog(@"[DEBUG] Camera INVALID, aborting");
        return;
    }

    uint64_t match = getMatch(matchGame);
    if (!isVaildPtr(match)) {
        NSLog(@"[DEBUG] match INVALID, aborting");
        return;
    }

    uint64_t myPawnObject = getLocalPlayer(match);
    if (!isVaildPtr(myPawnObject)) {
        NSLog(@"[DEBUG] LocalPlayer INVALID, aborting");
        return;
    }

    uint64_t mainCameraTransform = ReadAddr<uint64_t>(myPawnObject + 0x2B0);
    Vector3 myLocation = getPositionExt(mainCameraTransform);
    NSLog(@"[DEBUG] MyLocation = (%f, %f, %f)", myLocation.x, myLocation.y, myLocation.z);

    // PATCHED: Player List offset Match + 0xC8 -> Match + 0x158
    uint64_t player = ReadAddr<uint64_t>(match + 0x158);
    NSLog(@"[DEBUG] Player list ptr = 0x%llX", player);

    if (!isVaildPtr(player)) {
        NSLog(@"[DEBUG] Player list INVALID, trying old offset +0xC8");
        player = ReadAddr<uint64_t>(match + 0xC8);
        NSLog(@"[DEBUG] Fallback Player list = 0x%llX", player);
        if (!isVaildPtr(player)) {
            NSLog(@"[DEBUG] Both offsets failed, aborting");
            return;
        }
    }

    uint64_t tValue = ReadAddr<uint64_t>(player + 0x28);
    NSLog(@"[DEBUG] tValue = 0x%llX", tValue);

    if (!isVaildPtr(tValue)) {
        NSLog(@"[DEBUG] tValue INVALID, aborting");
        return;
    }

    int coutValue = ReadAddr<int>(tValue + 0x18);
    NSLog(@"[DEBUG] Player count = %d", coutValue);

    if (coutValue <= 0 || coutValue > 100) {
        NSLog(@"[DEBUG] Player count suspicious (%d), aborting", coutValue);
        return;
    }

    float *matrix = GetViewMatrix(camera);

    NSMutableArray<NSValue *> *boxesMutable = [NSMutableArray array];
    int countObject = 0;

    for (int i = 0; i < coutValue; i++) {
        uint64_t PawnObject = ReadAddr<uint64_t>(tValue + 0x20 + 8 * i);
        NSLog(@"[DEBUG] Player[%d] = 0x%llX", i, PawnObject);

        if (!isVaildPtr(PawnObject)) {
            NSLog(@"[DEBUG] Player[%d] invalid pointer", i);
            continue;
        }

        bool isLocalTeam = isLocalTeamMate(myPawnObject, PawnObject);
        if (isLocalTeam) {
            NSLog(@"[DEBUG] Player[%d] is teammate, skip", i);
            continue;
        }

        NSString *Name = GetNickName(PawnObject);
        NSLog(@"[DEBUG] Player[%d] name = '%@'", i, Name);

        // DEBUG: Don't skip empty name, just log it
        if (Name.length == 0) {
            NSLog(@"[DEBUG] Player[%d] empty name, but still processing", i);
        }

        int CurHP = get_CurHP(PawnObject);
        int MaxHP = get_MaxHP(PawnObject);
        NSLog(@"[DEBUG] Player[%d] HP = %d/%d", i, CurHP, MaxHP);

        uint64_t headPtr = getHead(PawnObject);
        uint64_t toePtr = getRightToeNode(PawnObject);

        if (!isVaildPtr(headPtr) || !isVaildPtr(toePtr)) {
            NSLog(@"[DEBUG] Player[%d] head/toe invalid, skip", i);
            continue;
        }

        Vector3 HeadLocation = getPositionExt(headPtr);
        HeadLocation.y += 0.2f;

        Vector3 RightToePos = getPositionExt(toePtr);

        NSLog(@"[DEBUG] Player[%d] Head=(%f,%f,%f) Toe=(%f,%f,%f)", 
              i, HeadLocation.x, HeadLocation.y, HeadLocation.z,
              RightToePos.x, RightToePos.y, RightToePos.z);

        Vector3 w2sHeadLocation = WorldToScreen(HeadLocation, matrix, sWidth, sHeight);
        Vector3 w2sRightToePos = WorldToScreen(RightToePos, matrix, sWidth, sHeight);

        NSLog(@"[DEBUG] Player[%d] W2S Head=(%f,%f) Toe=(%f,%f)",
              i, w2sHeadLocation.x, w2sHeadLocation.y, w2sRightToePos.x, w2sRightToePos.y);

        float dis = Vector3::Distance(myLocation, HeadLocation);
        NSLog(@"[DEBUG] Player[%d] distance = %f", i, dis);

        if (dis > 220.0f) {
            NSLog(@"[DEBUG] Player[%d] too far, skip", i);
            continue;
        }

        countObject++;

        float boxHeight = abs(w2sHeadLocation.y - w2sRightToePos.y);
        float boxWidth = boxHeight * 0.5f;
        float x = w2sHeadLocation.x - boxWidth * 0.5f;
        float y = w2sHeadLocation.y;

        NSLog(@"[DEBUG] Player[%d] BOX x=%f y=%f w=%f h=%f", i, x, y, boxWidth, boxHeight);

        ESPBox espBox;
        espBox.pos.x = x;
        espBox.pos.y = y;
        espBox.width = boxWidth;
        espBox.height = boxHeight;

        NSValue *val = [NSValue valueWithBytes:&espBox objCType:@encode(ESPBox)];
        [boxesMutable addObject:val];
    }

    NSLog(@"[DEBUG] ===== Total boxes: %d =====", countObject);

    self.boxes = boxesMutable;
    [self setNeedsDisplay];
}


@end
