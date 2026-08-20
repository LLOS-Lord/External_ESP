//
//  GameLogic.h
//  esp
//
//  Rewritten for TESTTIPA offsets (Unreal Engine / OOP pattern)
//

#ifndef GameLogic_h
#define GameLogic_h

#include <mach/mach.h>
#include <mach/vm_map.h>
#include <vector>
#include <string>
#include "Vector3.h"
#include "ESPData.h"
#include <Foundation/Foundation.h>

// ==========================================
// PlayerInfo struct (TESTTIPA compatible)
// ==========================================
struct PlayerInfo {
    uint64_t address = 0;
    Vector3 head;
    Vector3 toe;
    Vector3 hip;
    Vector3 lHand;
    Vector3 rHand;
    Vector3 lElbow;
    Vector3 rElbow;
    Vector3 lShoulder;
    Vector3 rShoulder;
    Vector3 lAnkle;
    Vector3 rAnkle;
    Vector3 lToe;
    Vector3 rToe;

    uint32_t hp = 0;
    uint32_t maxHp = 0;
    uint32_t team = 0;
    bool isDead = false;
    bool isBot = false;
    bool isVisible = false;
    std::string name;
};

// ==========================================
// CORE API
// ==========================================

// Lobby detection: returns true if player is in lobby/loading
bool IsAtLobby(void);

// Get match/game state pointer from GWorld chain
uint64_t getMatchGame(void);

// Get local player from match
uint64_t getLocalPlayer(uint64_t match);

// Get full player list
std::vector<PlayerInfo> getPlayerList(void);

// Camera / ViewMatrix
uint64_t GetCameraObject(void);
float* GetViewMatrix(uint64_t camera);
float getCameraFov(uint64_t camera);
Vector3 getCameraPosition(uint64_t camera);

// Bone position extraction from Transform Matrix at bone offset
Vector3 GetBonePosition(uint64_t player, uint32_t boneOffset);

// Player attributes
bool IsPlayerBot(uint64_t player);
bool IsPlayerVisible(uint64_t player);
uint32_t GetPlayerHP(uint64_t player, int index);
uint32_t GetPlayerMaxHP(uint64_t player, int index);
NSString* getPlayerName(uint64_t player);
uint32_t getPlayerTeamID(uint64_t player);
bool isValidPlayer(uint64_t player);

// World-to-screen projection
Vector3 WorldToScreenGL(Vector3 pos, float* matrix, float width, float height);
bool worldToScreen(Vector3 pos, float* outX, float* outY, int screenW, int screenH, uint64_t match);

// Lifecycle
void setupGameLogic(mach_port_t task);
void resetGameLogicCache(void);

#endif /* GameLogic_h */
