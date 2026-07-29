#include "Logger.h"

static FILE* g_logFile = NULL;

void ESPLogInit() {
    if (g_logFile) return;

    const char* paths[] = {
        "/var/mobile/Library/Caches/esp_debug.log",
        "/tmp/esp_debug.log",
        "/var/tmp/esp_debug.log",
        NULL
    };

    for (int i = 0; paths[i]; i++) {
        g_logFile = fopen(paths[i], "a");
        if (g_logFile) break;
    }

    if (!g_logFile) {
        g_logFile = fopen("esp_debug.log", "a");
    }

    if (g_logFile) {
        time_t now = time(NULL);
        fprintf(g_logFile, "\n\n========== ESP Debug Session Started: %s", ctime(&now));
        fflush(g_logFile);
    }
}

void ESPLog(const char* fmt, ...) {
    if (!g_logFile) ESPLogInit();
    if (!g_logFile) return;

    va_list args;
    va_start(args, fmt);

    time_t now = time(NULL);
    struct tm* tm_info = localtime(&now);
    char timebuf[32];
    strftime(timebuf, 32, "[%H:%M:%S]", tm_info);

    fprintf(g_logFile, "%s ", timebuf);
    vfprintf(g_logFile, fmt, args);
    fprintf(g_logFile, "\n");
    fflush(g_logFile);

    va_end(args);
}

void ESPLogClose() {
    if (g_logFile) {
        time_t now = time(NULL);
        fprintf(g_logFile, "========== ESP Debug Session Ended: %s\n", ctime(&now));
        fclose(g_logFile);
        g_logFile = NULL;
    }
}
