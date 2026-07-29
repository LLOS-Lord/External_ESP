#import <Foundation/Foundation.h>
#import "../drawing_view/esp.h"

@interface PlayerData : NSObject
@property (nonatomic, assign) Vector3 screenHead;
@property (nonatomic, assign) Vector3 screenToe;
@property (nonatomic, assign) float boxHeight;
@property (nonatomic, assign) float boxWidth;
@property (nonatomic, assign) int curHP;
@property (nonatomic, assign) int maxHP;
@property (nonatomic, assign) float distance;
@property (nonatomic, assign) bool isTeammate;
@property (nonatomic, strong) NSString *nickName;
@end

extern NSMutableArray<PlayerData *> *g_playerList;
extern float screenWidth;
extern float screenHeight;
