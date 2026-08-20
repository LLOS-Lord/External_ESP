#import "ESPData.h"

NSMutableArray<PlayerData *> *g_playerList = nil;
float screenWidth = 0;
float screenHeight = 0;
float g_cameraFov = 90.0f;
Vector3 g_cameraPos = {0, 0, 0};
float g_matrix[16] = {0};

@implementation PlayerData
@end
