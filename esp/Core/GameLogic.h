#pragma once
#include "MemoryUtils.h"
#include "UnityMath.h"

// Forward declarations
uint64_t getMatchGame(uint64_t base);
uint64_t CameraMain(uint64_t matchGame);
uint64_t getMatch(uint64_t matchGame);
uint64_t getLocalPlayer(uint64_t match);
int getPlayerList(uint64_t match, uint64_t* outPlayers, int maxCount);

uint64_t getHeadTransform(uint64_t player);
uint64_t getToeTransform(uint64_t player);
uint32_t getTeamID(uint64_t player);
bool isLocalTeamMate(uint64_t localPlayer, uint64_t player);
NSString* getPlayerName(uint64_t player);
int get_CurHP(uint64_t player);
int get_MaxHP(uint64_t player);

float* GetViewMatrix(uint64_t cameraMain);
float getCameraFov(uint64_t camera);
Vector3 getCameraPosition(uint64_t camera);
Vector3 GetTransformPosition(uint64_t transform);

// NEW: player validation helper
bool isValidPlayer(uint64_t player);
