#ifndef OFFSETS_H
#define OFFSETS_H

#include <cstdint>

// ============================================================
// OFFSETS EXTRACTED FROM Offsets.cs
// ============================================================

// Base / Init
#define OFFSET_InitBase           0xA988FDC
#define OFFSET_StaticClass        0x5C

// Match Related
#define OFFSET_CurrentMatch       0x50
#define OFFSET_MatchStatus        0x8C
#define OFFSET_LocalPlayer        0x94
#define OFFSET_LocalPlayerAttributes 0x4BC
#define OFFSET_DictionaryEntities 0x68

// Player
#define OFFSET_TeamID             0x29C
#define OFFSET_Player_IsDead      0x50
#define OFFSET_Player_Name        0x2DC
#define OFFSET_Player_Data        0x48
#define OFFSET_Player_ShadowBase  0x18B8
#define OFFSET_XPose              0x78
#define OFFSET_AvatarManager      0x4C0
#define OFFSET_Avatar             0xA8
#define OFFSET_Avatar_IsVisible   0x95
#define OFFSET_Avatar_Data        0x14
#define OFFSET_Avatar_Data_IsTeam 0x59
#define OFFSET_Avatar_Data_IsBot  0x2E4
#define OFFSET_PlayerID           0x268
#define OFFSET_BaseProfileInfo    0x18CC
#define OFFSET_IsClientBot        0x2E4

// Camera
#define OFFSET_FollowCamera       0x450
#define OFFSET_Camera             0x18
#define OFFSET_MainCameraTransform 0x24C
#define OFFSET_AimRotation        0x400
#define OFFSET_ViewMatrix         0xE8

// Loot / ESP Items
#define OFFSET_Loot_ID            0x8
#define OFFSET_Loot_Pos           0x48
#define OFFSET_LevelObjectManager 0x60
#define OFFSET_LevelObjectList    0x30

// Observer
#define OFFSET_CurrentObserver    0xB4
#define OFFSET_ObserverPlayer     0x28

// Weapon
#define OFFSET_Weapon             0x3F4
#define OFFSET_WeaponData         0x58
#define OFFSET_WeaponRecoil       0xC
#define OFFSET_UnkPlayerWeaponInfoClass 0x4A8
#define OFFSET_IsCombineWeapon    0xD8
#define OFFSET_WeaponOnHand       0x54
#define OFFSET_CombineWeaponOnHand 0x58
#define OFFSET_WeaponInfo         0x64
#define OFFSET_WeaponID           0x14
#define OFFSET_Weapon_Damage      0x8

// Silent Aim / Aim Info
#define OFFSET_LastAimingInfoFromWeapon 0x978
#define OFFSET_StartPosition      0x38
#define OFFSET_RayDir             0x2C
#define OFFSET_LockedAimingCollider 0x54
#define OFFSET_HeadCollider       0x4A4

// Aiming (firing/rotate)
#define OFFSET_LocalPlayerIsFiring 0x48C
#define OFFSET_SilentAimShoot     0x48C
#define OFFSET_SilentAimRotate    0x4A0

// Aimkill
#define OFFSET_LocalPlayer_Target 0x48
#define OFFSET_Enemy_Knockdowns   0x68
#define OFFSET_Player_Inventory   0x1B0

// Misc
#define OFFSET_PlayerAttributes   0x4B0
#define OFFSET_NoReload           0x99
#define OFFSET_RunSpeedUpScale    0x1D8
#define OFFSET_FallingSpeedUpScale 0x1B8
#define OFFSET_GameTimer          0x10
#define OFFSET_FixedDeltaTime     0x24
#define OFFSET_BuffWeaponMoveSpeedScale 0xBC
#define OFFSET_InSnowSlideWayDashing 0x15E8
#define OFFSET_m_ReviveHP         0xF4
#define OFFSET_isBotOffs          0xC0

// Jump / misc
#define OFFSET_highjumpff         0x893EC6C

// Legacy aim aliases
#define OFFSET_sAim1              0x540
#define OFFSET_sAim2              0x978
#define OFFSET_sAim3              0x38
#define OFFSET_sAim4              0x2C

// Portuguese aim aliases
#define OFFSET_pomba              0x540
#define OFFSET_bisteca            0x978
#define OFFSET_arma               0x38
#define OFFSET_tiro               0x2C

// Teleport Mark
#define OFFSET_TeleportMark_UIInGameScene       0x8
#define OFFSET_TeleportMark_BigMapCtrl          0x218
#define OFFSET_TeleportMark_MapContentCtrl      0x54
#define OFFSET_TeleportMark_LocalMapMarkController 0x90
#define OFFSET_TeleportMark_MarkPos             0x58

#endif // OFFSETS_H
