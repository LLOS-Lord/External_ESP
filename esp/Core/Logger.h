#ifndef Logger_h
#define Logger_h

#include <stdio.h>
#include <stdarg.h>
#include <time.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

void ESPLogInit();
void ESPLog(const char* fmt, ...);
void ESPLogClose();

#ifdef __cplusplus
}
#endif

#endif
