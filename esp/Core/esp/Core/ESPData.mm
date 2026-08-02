#import "ESPData.h"

@implementation PlayerData
@end

NSMutableArray<PlayerData *> *g_playerList = nil;
float screenWidth = 0.0f;
float screenHeight = 0.0f;
float g_cameraFov = 0.0f;
Vector3 g_cameraPos;
float g_matrix[16] = {0};
