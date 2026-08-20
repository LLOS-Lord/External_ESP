#ifndef OffsetResolver_h
#define OffsetResolver_h

#include <cstdint>
#include <mach/mach.h>

// ==========================================
// RUNTIME RESOLVED OFFSETS
// ==========================================
struct ResolvedOffsets {
    bool resolved = false;
    bool hasInstance = false;
    uint64_t gameManagerInstance = 0;

    // Core chain offsets (legacy Unity style)
    uint32_t off_GM_To_MatchGame = 0x50;
    uint32_t off_Match_To_LocalPlayer = 0x30;
    uint32_t off_GM_To_Dict = 0x40;

    // MatchGame internals
    uint32_t off_Match_To_Camera = 0x58;

    // Player object offsets (legacy)
    uint32_t off_Player_To_Head = 0x48;
    uint32_t off_Player_To_Toe = 0x50;
    uint32_t off_Player_To_HP = 0xA0;
    uint32_t off_Player_To_MaxHP = 0xA4;
    uint32_t off_Player_To_Team = 0xB0;
    uint32_t off_Player_To_Name = 0xC0;

    // Transform
    uint32_t off_Transform_To_Pos = 0x90;
};

extern ResolvedOffsets g_resolved;

// ==========================================
// AUTO RESOLVE API
// ==========================================

bool resolveOffsets(uint64_t moduleBase, uint64_t moduleSize);
bool resolveOffsetsHeuristic(uint64_t moduleBase, uint64_t moduleSize);
bool tryHardcodedOffsets(uint64_t moduleBase);
void logResolvedOffsets();

#endif /* OffsetResolver_h */
