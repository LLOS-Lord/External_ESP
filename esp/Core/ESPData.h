#ifndef ESPData_h
#define ESPData_h

#import <Foundation/Foundation.h>
#import "Vector3.h"
#import "../drawing_view/esp.h"

@interface PlayerData : NSObject

// --- Screen positions ---
@property (nonatomic, assign) Vector3 screenHead;
@property (nonatomic, assign) Vector3 screenToe;
@property (nonatomic, assign) float boxHeight;
@property (nonatomic, assign) float boxWidth;
@property (nonatomic, assign) float distance;
@property (nonatomic, assign) bool isTeammate;

// --- World positions (bones) ---
@property (nonatomic, assign) uint64_t address;
@property (nonatomic, assign) Vector3 head;
@property (nonatomic, assign) Vector3 toe;
@property (nonatomic, assign) Vector3 hip;
@property (nonatomic, assign) Vector3 lHand;
@property (nonatomic, assign) Vector3 rHand;
@property (nonatomic, assign) Vector3 lElbow;
@property (nonatomic, assign) Vector3 rElbow;
@property (nonatomic, assign) Vector3 lShoulder;
@property (nonatomic, assign) Vector3 rShoulder;
@property (nonatomic, assign) Vector3 lAnkle;
@property (nonatomic, assign) Vector3 rAnkle;
@property (nonatomic, assign) Vector3 lToe;
@property (nonatomic, assign) Vector3 rToe;

// --- Stats ---
@property (nonatomic, assign) int hp;
@property (nonatomic, assign) int maxHp;
@property (nonatomic, assign) int team;
@property (nonatomic, assign) bool isEnemy;
@property (nonatomic, assign) bool isBot;
@property (nonatomic, assign) bool isVisible;
@property (nonatomic, strong) NSString *name;

// --- Legacy fields ---
@property (nonatomic, assign) int curHP;
@property (nonatomic, assign) int maxHP;
@property (nonatomic, strong) NSString *nickName;

@end

extern NSMutableArray<PlayerData *> *g_playerList;
extern float screenWidth;
extern float screenHeight;
extern float g_cameraFov;
extern Vector3 g_cameraPos;
extern float g_matrix[16];

#endif /* ESPData_h */
