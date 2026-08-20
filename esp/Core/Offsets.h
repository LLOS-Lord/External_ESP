#ifndef Offsets_h
#define Offsets_h

#include <cstdint>

// ==========================================
// TESTTIPA OFFSETS - Extracted from ARM64 static analysis
// Game: Unreal Engine based (GWorld/GameInstance pattern)
// ==========================================

// ==========================================
// ROOT / GLOBAL OFFSETS
// ==========================================

// GWorld pointer offset from ModuleBase
#define OFFSET_GWorld           0x0BFD8978

// GWorld -> MatchGame/GameState pointer
#define OFFSET_GWorld_To_Match  0xB8

// MatchGame validity check offset (lobby detection)
#define OFFSET_Match_Valid      0x8

// ==========================================
// CAMERA / VIEW MATRIX (Pointer Chain)
// ==========================================
// Camera object chain from some base:
// base + 0x10 -> +0x48 -> +0x80 -> +0xC0 = ViewMatrix (16 floats)
#define OFFSET_Cam_Chain1       0x10
#define OFFSET_Cam_Chain2       0x48
#define OFFSET_Cam_Chain3       0x80
#define OFFSET_Cam_Matrix       0xC0

// ==========================================
// PLAYER OBJECT OFFSETS
// ==========================================

// IsBot: read 1 byte bool
#define OFFSET_Player_IsBot     0x438

// IsVisible: read pointer (8 bytes) -> +0x130 -> +0x180
#define OFFSET_Player_IsVisible     0xA40
#define OFFSET_Player_IsVisible_1   0x130
#define OFFSET_Player_IsVisible_2   0x180

// ==========================================
// HP POINTER CHAIN
// ==========================================
// [[[PlayerObject + 0x70] + 0x10] + (Index * 8) + 0x20] + 0x18
#define OFFSET_Player_HP_Base   0x70
#define OFFSET_HP_Base_1        0x10
#define OFFSET_HP_IndexMul      8
#define OFFSET_HP_Base_2        0x20
#define OFFSET_HP_Final         0x18

// ==========================================
// BONE OFFSETS (Transform Matrix offsets)
// ==========================================
#define OFFSET_Bone_Hip         0x640
#define OFFSET_Bone_Head        0x648
#define OFFSET_Bone_LShoulder   0x658
#define OFFSET_Bone_RShoulder   0x660
#define OFFSET_Bone_LAnkle      0x670
#define OFFSET_Bone_RAnkle      0x678
#define OFFSET_Bone_LToe        0x680
#define OFFSET_Bone_RToe        0x688
#define OFFSET_Bone_RHand       0x6B0
#define OFFSET_Bone_LHand       0x6B8
#define OFFSET_Bone_RElbow      0x6C0
#define OFFSET_Bone_LElbow      0x6C8

// ==========================================
// LEGACY UNITY OFFSETS (kept for fallback / heuristic)
// ==========================================
#define OFFSET_InitBase         0xA988FDC
#define OFFSET_StaticClass      0x10
#define OFFSET_DictionaryEntities 0x40
#define OFFSET_CurrentMatch     0x50
#define OFFSET_LocalPlayer      0x30
#define OFFSET_CameraMain       0x58

// Legacy player offsets (Unity style)
#define OFFSET_Head             0x48
#define OFFSET_Toe              0x50
#define OFFSET_CurHP            0xA0
#define OFFSET_MaxHP            0xA4
#define OFFSET_TeamID           0xB0
#define OFFSET_NickName         0xC0
#define OFFSET_Position         0x90

#endif /* Offsets_h */
