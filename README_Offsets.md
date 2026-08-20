# ESP Offset Update - Analysis

## Files Modified
- `esp/Core/Offsets.h` - **NEW**: Centralized offset definitions extracted from `Offsets.cs`
- `esp/Core/GameLogic.mm` - **UPDATED**: All hardcoded offsets replaced with macros from `Offsets.h`

## Offset Mapping Analysis

### Base / Init Structure
```
ModuleBase + InitBase(0xA988FDC) → GameManager/StaticClass pointer
    + StaticClass(0x5C) → static fields
        + CurrentMatch(0x50) → Match instance
```

### Match Structure
```
Match:
    + MatchStatus(0x8C)      → uint32 match status
    + LocalPlayer(0x94)      → LocalPlayer pointer
    + DictionaryEntities(0x68) → Player Dictionary/List
    + LocalPlayerAttributes(0x4BC) → Local player attributes
```

### Player Structure
```
Player:
    + TeamID(0x29C)          → uint32 team ID
    + Player_Name(0x2DC)     → Il2CppString* nickname
    + Player_IsDead(0x50)    → bool is dead
    + Player_Data(0x48)      → PlayerData*
    + AvatarManager(0x4C0)   → AvatarManager*
        + Avatar(0xA8)       → Avatar*
            + Avatar_Data(0x14) → Transform/Bone data
    + XPose(0x78)            → Transform* (fallback)
    + PlayerAttributes(0x4B0) → Attributes* (HP/MaxHP)
    + PlayerID(0x268)        → uint32 player ID
    + BaseProfileInfo(0x18CC) → ProfileInfo*
```

### Camera Structure
```
Match/Base + FollowCamera(0x450) → FollowCamera*
    + Camera(0x18)           → Camera*
        + ViewMatrix(0xE8)   → float[16] view matrix
        + MainCameraTransform(0x24C) → Transform* position
```

## Key Changes in GameLogic.mm

| Function | Old Offset | New Offset | Notes |
|----------|-----------|-----------|-------|
| `getMatchGame` | `base + 0x9985B70` | `base + InitBase(0xA988FDC)` | New init pointer |
| `getMatchGame` | `+ 0xB8` → `+ 0x8` | `+ StaticClass(0x5C)` → `+ CurrentMatch(0x50)` | New static class layout |
| `CameraMain` | `matchGame + 0xD8` → `+ 0x20` | `matchGame + FollowCamera(0x450)` → `+ Camera(0x18)` | New camera chain |
| `getMatch` | `matchGame + 0x90` | `matchGame` (same) | CurrentMatch is now Match |
| `getLocalPlayer` | `match + 0xD8` | `match + LocalPlayer(0x94)` | New local player offset |
| `getPlayerList` | `match + 0x158` | `match + DictionaryEntities(0x68)` | New entity container |
| `getTeamID` | `player + 0x3CC` | `player + TeamID(0x29C)` | New team offset |
| `getPlayerName` | `player + 0x430` | `player + Player_Name(0x2DC)` | New name offset |
| `getHeadTransform` | `player + 0x698` | `player + AvatarManager(0x4C0)` → `+ Avatar(0xA8)` | New avatar chain |
| `get_CurHP` | `player + 0x244` | `player + PlayerAttributes(0x4B0)` → attributes + 0x0 | New HP path |
| `get_MaxHP` | `player + 0x288` | `player + PlayerAttributes(0x4B0)` → attributes + 0x4 | New MaxHP path |
| `GetViewMatrix` | `camera + 0x30/0x40/0x50` | `camera + ViewMatrix(0xE8)` | New matrix offset |
| `getCameraPosition` | `camera + 0x30` | `camera + MainCameraTransform(0x24C)` | New cam pos |

## Additional Offsets Available (Not Yet Used)

### Weapon
- `Weapon(0x3F4)`, `WeaponData(0x58)`, `WeaponRecoil(0xC)`, `WeaponID(0x14)`, `Weapon_Damage(0x8)`

### Silent Aim
- `LastAimingInfoFromWeapon(0x978)`, `StartPosition(0x38)`, `RayDir(0x2C)`, `HeadCollider(0x4A4)`

### Misc
- `NoReload(0x99)`, `RunSpeedUpScale(0x1D8)`, `FallingSpeedUpScale(0x1B8)`, `BuffWeaponMoveSpeedScale(0xBC)`

### Teleport
- `TeleportMark_UIInGameScene(0x8)`, `TeleportMark_BigMapCtrl(0x218)`, `TeleportMark_MarkPos(0x58)`

## Notes
- The new offset structure suggests a different game version/build than the original code.
- `DictionaryEntities` may be either a `List<Player>` or `Dictionary<int, Player>`. The code tries both.
- `PlayerAttributes` is used as the new source for HP/MaxHP since direct offsets are not present in the new dump.
- Multiple fallback paths are kept for compatibility during testing.
