#ifndef UnityMath_h
#define UnityMath_h

#import "Vector3.h"
#import "Quaternion.h"
#import "MemoryUtils.h"
#import "utf.h"
#import <Foundation/Foundation.h>

#pragma mark - Struct Game

struct Vector4 {
    float x,y,z,w;
};

struct TMatrix {
    Vector4 position;
    Quaternion rotation;
    Vector4 scale;
};

struct COW_GamePlay_PlayerID_o {
    uint32_t m_Value;
    uint32_t m_ID;
    uint8_t m_TeamID;
    uint8_t m_ShortID;
    uint64_t m_IDMask;
};

#pragma mark - Function Unity

Vector3 WorldToScreen(Vector3 obj, float *matrix, float screenX, float screenY);
Vector3 getPositionExt(uint64_t transObj2);
NSString *GetNickName(uint64_t PawnObject);

#endif