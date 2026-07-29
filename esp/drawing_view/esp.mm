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
        for (CALayer *layer in self.layers)
        {
            [layer removeFromSuperlayer];
        }
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
    CFTimeInterval t = CACurrentMediaTime();
    CGSize size = self.bounds.size;

    const NSInteger boxCount = 10;
    const CGFloat baseWidth = 60.0;
    const CGFloat baseHeight = 120.0;

    NSMutableArray<NSValue *> *boxesMutable = [NSMutableArray arrayWithCapacity:boxCount];
    int countObject = 0;

    if (Moudule_Base == -1) return;

    uint64_t matchGame = getMatchGame(Moudule_Base);
    uint64_t camera = CameraMain(matchGame);
    if (!isVaildPtr(camera)) return;

    uint64_t match = getMatch(matchGame);
    if (!isVaildPtr(match)) return;

    // PATCHED: Local Player offset changed Match + 0x58 -> Match + 0xD8
    uint64_t myPawnObject = getLocalPlayer(match);
    if (!isVaildPtr(myPawnObject)) return;

    // NOTE: mainCameraTransform offset +0x2B0 not confirmed in new dump.
    // If ESP drifts, verify this offset with Cheat Engine.
    uint64_t mainCameraTransform = ReadAddr<uint64_t>(myPawnObject + 0x2B0);
    Vector3 myLocation = getPositionExt(mainCameraTransform);

    // PATCHED: Player List offset changed Match + 0xC8 -> Match + 0x158
    uint64_t player = ReadAddr<uint64_t>(match + 0x158);
    uint64_t tValue = ReadAddr<uint64_t>(player + 0x28);
    int coutValue = ReadAddr<int>(tValue + 0x18);

    float *matrix = GetViewMatrix(camera);

    for (int i = 0; i < coutValue; i++) {
        uint64_t PawnObject = ReadAddr<uint64_t>(tValue + 0x20 + 8 * i);
        if (!isVaildPtr(PawnObject)) continue;

        bool isLocalTeam = isLocalTeamMate(myPawnObject, PawnObject);
        if (isLocalTeam) continue;

        NSString *Name = GetNickName(PawnObject);
        if (Name.length == 0) continue;

        int CurHP = get_CurHP(PawnObject);
        int MaxHP = get_MaxHP(PawnObject);

        // PATCHED: Head/Toe fields removed. Using guessed offsets from ITransformNode array.
        // Head: +0x698 (OKOLMFJKGEC - only Transform* in array)
        // Toe: +0x630 (first ITransformNode - GUESS, may need adjustment)
        Vector3 HeadLocation     = getPositionExt(getHead(PawnObject));
        HeadLocation.y           += 0.2f;

        Vector3 RightToePos      = getPositionExt(getRightToeNode(PawnObject));

        Vector3 w2sHeadLocation  = WorldToScreen(HeadLocation, matrix, sWidth, sHeight);
        Vector3 w2sRightToePos   = WorldToScreen(RightToePos, matrix, sWidth, sHeight);

        float dis = Vector3::Distance(myLocation, HeadLocation);
        if (dis > 220.0f) continue;

        countObject++;

        float boxHeight = abs(w2sHeadLocation.y - w2sRightToePos.y);
        float boxWidth = boxHeight * 0.5f;
        float x = w2sHeadLocation.x - boxWidth * 0.5f;
        float y = w2sHeadLocation.y;
        CGRect box = CGRectMake(x, y, boxWidth, boxHeight);

        ESPBox espBox;
        espBox.pos.x = x;
        espBox.pos.y = y;
        espBox.width = boxWidth;
        espBox.height = boxHeight;

        NSValue *val = [NSValue valueWithBytes:&espBox objCType:@encode(ESPBox)];
        [boxesMutable addObject:val];
    }

    NSLog(@"[Flork] Count: %d", countObject);

    self.boxes = boxesMutable;
    [self setNeedsDisplay];
}


@end
