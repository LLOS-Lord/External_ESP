#ifndef MemoryPattern_h
#define MemoryPattern_h

#include <cstdint>
#include <cstddef>

// ==========================================
// PATTERN SCAN
// ==========================================

uint64_t patternScan(uint64_t start, size_t size, const char* pattern);
uint64_t patternScanFirst(uint64_t start, size_t size, const char* pattern);

// ==========================================
// GAME MANAGER RESOLVE
// ==========================================

uint64_t autoResolveInitBase(uint64_t moduleBase, uint64_t moduleSize);
uint64_t autoResolveGameManager(uint64_t moduleBase, uint64_t moduleSize);

#endif /* MemoryPattern_h */
