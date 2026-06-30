#import <ApplicationServices/ApplicationServices.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#include <dlfcn.h>
#include <math.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>

typedef const void *MTDeviceRef;

typedef struct {
    float x;
    float y;
} MTPoint;

typedef struct {
    MTPoint position;
    MTPoint velocity;
} MTVector;

typedef struct {
    int32_t frame;
    double timestamp;
    int32_t pathIndex;
    int32_t state;
    int32_t fingerID;
    int32_t handID;
    MTVector normalized;
    float zTotal;
    int32_t field9;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector absolute;
    int32_t field14;
    int32_t field15;
    float zDensity;
} MTTouch;

typedef void (*MTContactFrameCallback)(MTDeviceRef device,
                                       MTTouch *touches,
                                       int32_t touchCount,
                                       double timestamp,
                                       int32_t frame);
typedef CFArrayRef (*MTDeviceCreateListFn)(void);
typedef int (*MTDeviceStartFn)(MTDeviceRef device, int runMode);
typedef void (*MTDeviceStopFn)(MTDeviceRef device);
typedef void (*MTRegisterContactFrameCallbackFn)(MTDeviceRef device, MTContactFrameCallback callback);
typedef void (*MTUnregisterContactFrameCallbackFn)(MTDeviceRef device, MTContactFrameCallback callback);
typedef bool (*MTDeviceIsBuiltInFn)(MTDeviceRef device);
typedef int (*MTDeviceGetDeviceIDFn)(MTDeviceRef device, uint64_t *deviceID);
typedef int (*MTDeviceGetSensorSurfaceDimensionsFn)(MTDeviceRef device, int32_t *width, int32_t *height);

typedef enum {
    PolicyAllDead = 0,
    PolicyAnyDead = 1,
} BlockPolicy;

typedef struct {
    double leftNorm;
    double rightNorm;
    double topNorm;
    double bottomNorm;
    double leftCm;
    double rightCm;
    double topCm;
    double bottomCm;
    bool hasLeftCm;
    bool hasRightCm;
    bool hasTopCm;
    bool hasBottomCm;
    bool invertX;
    bool invertY;
    int deviceIndex;
    int graceMs;
    BlockPolicy policy;
    bool listDevices;
    bool monitorOnly;
    bool verbose;
} Options;

typedef struct {
    bool present;
    int32_t pathIndex;
    bool startedDead;
    double x;
    double y;
    uint64_t lastSeenMs;
} TouchSlot;

typedef struct {
    void *handle;
    MTDeviceCreateListFn createList;
    MTDeviceStartFn start;
    MTDeviceStopFn stop;
    MTRegisterContactFrameCallbackFn registerContactFrame;
    MTUnregisterContactFrameCallbackFn unregisterContactFrame;
    MTDeviceIsBuiltInFn isBuiltIn;
    MTDeviceGetDeviceIDFn getDeviceID;
    MTDeviceGetSensorSurfaceDimensionsFn getSensorSurfaceDimensions;
} MultitouchAPI;

static Options gOptions = {
    .leftNorm = 0.125,
    .rightNorm = 0.125,
    .topNorm = 0.0,
    .bottomNorm = 0.0,
    .leftCm = 0.0,
    .rightCm = 0.0,
    .topCm = 0.0,
    .bottomCm = 0.0,
    .hasLeftCm = false,
    .hasRightCm = false,
    .hasTopCm = false,
    .hasBottomCm = false,
    .invertX = false,
    .invertY = false,
    .deviceIndex = -1,
    .graceMs = 120,
    .policy = PolicyAllDead,
    .listDevices = false,
    .monitorOnly = false,
    .verbose = false,
};

static MultitouchAPI gMT;
static MTDeviceRef gSelectedDevice = NULL;
static CFMachPortRef gEventTap = NULL;
static TouchSlot gTouches[64];
static atomic_ullong gBlockUntilMs = 0;
static atomic_uint gSuppressedEvents = 0;
static atomic_uint gBlockedFrames = 0;
static atomic_uint gActiveTouches = 0;
static volatile sig_atomic_t gShouldStop = 0;

static uint64_t nowMs(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return ((uint64_t)tv.tv_sec * 1000ULL) + ((uint64_t)tv.tv_usec / 1000ULL);
}

static double clamp01(double value) {
    if (value < 0.0) return 0.0;
    if (value > 1.0) return 1.0;
    return value;
}

static void printUsage(const char *program) {
    fprintf(stderr,
            "Usage: %s [options]\n"
            "\n"
            "Options:\n"
            "  --list-devices              Print multitouch devices and exit.\n"
            "  --monitor                   Print touches and block decisions; do not suppress events.\n"
            "  --device INDEX              Use device at INDEX from --list-devices.\n"
            "  --left N                    Left dead zone as normalized width, default 0.125.\n"
            "  --right N                   Right dead zone as normalized width, default 0.125.\n"
            "  --top N                     Top dead zone as normalized height, default 0.\n"
            "  --bottom N                  Bottom dead zone as normalized height, default 0.\n"
            "  --left-cm CM                Left dead zone in cm, using device surface width.\n"
            "  --right-cm CM               Right dead zone in cm, using device surface width.\n"
            "  --top-cm CM                 Top dead zone in cm, using device surface height.\n"
            "  --bottom-cm CM              Bottom dead zone in cm, using device surface height.\n"
            "  --policy all|any            all: block only if all active touches began dead; any: stricter.\n"
            "                              Default: all.\n"
            "  --grace-ms MS               Continue blocking briefly after a dead touch frame. Default 120.\n"
            "  --invert-x                  Flip x coordinate if calibration shows left/right inverted.\n"
            "  --invert-y                  Flip y coordinate if calibration shows top/bottom inverted.\n"
            "  --verbose                   Print block statistics once per second.\n"
            "  --help                      Show this help.\n"
            "\n"
            "Examples:\n"
            "  %s --list-devices\n"
            "  %s --monitor --left-cm 2 --right-cm 2\n"
            "  %s --left-cm 1.8 --right-cm 1.8 --policy all\n",
            program, program, program, program);
}

static bool parseDouble(const char *s, double *out) {
    char *end = NULL;
    double value = strtod(s, &end);
    if (end == s || *end != '\0' || isnan(value) || isinf(value)) {
        return false;
    }
    *out = value;
    return true;
}

static bool parseInt(const char *s, int *out) {
    char *end = NULL;
    long value = strtol(s, &end, 10);
    if (end == s || *end != '\0') {
        return false;
    }
    *out = (int)value;
    return true;
}

static bool parseArgs(int argc, const char **argv) {
    for (int i = 1; i < argc; i++) {
        const char *arg = argv[i];
        const char *next = (i + 1 < argc) ? argv[i + 1] : NULL;

        if (strcmp(arg, "--help") == 0 || strcmp(arg, "-h") == 0) {
            printUsage(argv[0]);
            exit(0);
        } else if (strcmp(arg, "--list-devices") == 0) {
            gOptions.listDevices = true;
        } else if (strcmp(arg, "--monitor") == 0) {
            gOptions.monitorOnly = true;
            gOptions.verbose = true;
        } else if (strcmp(arg, "--verbose") == 0) {
            gOptions.verbose = true;
        } else if (strcmp(arg, "--invert-x") == 0) {
            gOptions.invertX = true;
        } else if (strcmp(arg, "--invert-y") == 0) {
            gOptions.invertY = true;
        } else if (strcmp(arg, "--device") == 0 && next) {
            if (!parseInt(next, &gOptions.deviceIndex)) return false;
            i++;
        } else if (strcmp(arg, "--left") == 0 && next) {
            if (!parseDouble(next, &gOptions.leftNorm)) return false;
            gOptions.leftNorm = clamp01(gOptions.leftNorm);
            i++;
        } else if (strcmp(arg, "--right") == 0 && next) {
            if (!parseDouble(next, &gOptions.rightNorm)) return false;
            gOptions.rightNorm = clamp01(gOptions.rightNorm);
            i++;
        } else if (strcmp(arg, "--top") == 0 && next) {
            if (!parseDouble(next, &gOptions.topNorm)) return false;
            gOptions.topNorm = clamp01(gOptions.topNorm);
            i++;
        } else if (strcmp(arg, "--bottom") == 0 && next) {
            if (!parseDouble(next, &gOptions.bottomNorm)) return false;
            gOptions.bottomNorm = clamp01(gOptions.bottomNorm);
            i++;
        } else if (strcmp(arg, "--left-cm") == 0 && next) {
            if (!parseDouble(next, &gOptions.leftCm)) return false;
            gOptions.hasLeftCm = true;
            i++;
        } else if (strcmp(arg, "--right-cm") == 0 && next) {
            if (!parseDouble(next, &gOptions.rightCm)) return false;
            gOptions.hasRightCm = true;
            i++;
        } else if (strcmp(arg, "--top-cm") == 0 && next) {
            if (!parseDouble(next, &gOptions.topCm)) return false;
            gOptions.hasTopCm = true;
            i++;
        } else if (strcmp(arg, "--bottom-cm") == 0 && next) {
            if (!parseDouble(next, &gOptions.bottomCm)) return false;
            gOptions.hasBottomCm = true;
            i++;
        } else if (strcmp(arg, "--grace-ms") == 0 && next) {
            if (!parseInt(next, &gOptions.graceMs)) return false;
            if (gOptions.graceMs < 0) gOptions.graceMs = 0;
            i++;
        } else if (strcmp(arg, "--policy") == 0 && next) {
            if (strcmp(next, "all") == 0) {
                gOptions.policy = PolicyAllDead;
            } else if (strcmp(next, "any") == 0) {
                gOptions.policy = PolicyAnyDead;
            } else {
                return false;
            }
            i++;
        } else {
            fprintf(stderr, "Unknown or incomplete option: %s\n", arg);
            return false;
        }
    }
    return true;
}

static void *requireSymbol(void *handle, const char *name) {
    void *symbol = dlsym(handle, name);
    if (!symbol) {
        fprintf(stderr, "Missing MultitouchSupport symbol: %s\n", name);
        exit(2);
    }
    return symbol;
}

static void loadMultitouchAPI(void) {
    const char *path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport";
    gMT.handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL);
    if (!gMT.handle) {
        fprintf(stderr, "Could not load %s: %s\n", path, dlerror());
        exit(2);
    }

    gMT.createList = (MTDeviceCreateListFn)requireSymbol(gMT.handle, "MTDeviceCreateList");
    gMT.start = (MTDeviceStartFn)requireSymbol(gMT.handle, "MTDeviceStart");
    gMT.stop = (MTDeviceStopFn)requireSymbol(gMT.handle, "MTDeviceStop");
    gMT.registerContactFrame =
        (MTRegisterContactFrameCallbackFn)requireSymbol(gMT.handle, "MTRegisterContactFrameCallback");
    gMT.unregisterContactFrame =
        (MTUnregisterContactFrameCallbackFn)requireSymbol(gMT.handle, "MTUnregisterContactFrameCallback");
    gMT.isBuiltIn = (MTDeviceIsBuiltInFn)dlsym(gMT.handle, "MTDeviceIsBuiltIn");
    gMT.getDeviceID = (MTDeviceGetDeviceIDFn)dlsym(gMT.handle, "MTDeviceGetDeviceID");
    gMT.getSensorSurfaceDimensions =
        (MTDeviceGetSensorSurfaceDimensionsFn)dlsym(gMT.handle, "MTDeviceGetSensorSurfaceDimensions");
}

static bool getSurfaceDimensions(MTDeviceRef device, int32_t *widthHundredMm, int32_t *heightHundredMm) {
    if (!gMT.getSensorSurfaceDimensions) {
        return false;
    }
    int32_t width = 0;
    int32_t height = 0;
    int result = gMT.getSensorSurfaceDimensions(device, &width, &height);
    if (result == 0 && width > 0 && height > 0) {
        *widthHundredMm = width;
        *heightHundredMm = height;
        return true;
    }
    if (width > 0 && height > 0) {
        *widthHundredMm = width;
        *heightHundredMm = height;
        return true;
    }
    return false;
}

static void printDevice(int index, MTDeviceRef device) {
    bool builtIn = gMT.isBuiltIn ? gMT.isBuiltIn(device) : false;
    uint64_t deviceID = 0;
    if (gMT.getDeviceID) {
        (void)gMT.getDeviceID(device, &deviceID);
    }
    int32_t width = 0;
    int32_t height = 0;
    bool hasDims = getSurfaceDimensions(device, &width, &height);

    fprintf(stderr, "[%d] id=%llu builtIn=%s",
            index,
            (unsigned long long)deviceID,
            builtIn ? "yes" : "no");

    if (hasDims) {
        fprintf(stderr,
                " surface=%.2fcm x %.2fcm",
                (double)width / 1000.0,
                (double)height / 1000.0);
    } else {
        fprintf(stderr, " surface=unknown");
    }
    fprintf(stderr, "\n");
}

static MTDeviceRef chooseDevice(CFArrayRef devices) {
    CFIndex count = CFArrayGetCount(devices);
    if (count <= 0) {
        fprintf(stderr, "No multitouch devices found.\n");
        exit(3);
    }

    if (gOptions.deviceIndex >= 0) {
        if (gOptions.deviceIndex >= count) {
            fprintf(stderr, "Device index %d is out of range. Available: 0..%ld\n",
                    gOptions.deviceIndex,
                    (long)count - 1);
            exit(3);
        }
        return CFArrayGetValueAtIndex(devices, gOptions.deviceIndex);
    }

    CFIndex bestIndex = 0;
    double bestScore = -1.0;
    for (CFIndex i = 0; i < count; i++) {
        MTDeviceRef device = CFArrayGetValueAtIndex(devices, i);
        bool builtIn = gMT.isBuiltIn ? gMT.isBuiltIn(device) : false;
        int32_t width = 0;
        int32_t height = 0;
        double area = 1.0;
        if (getSurfaceDimensions(device, &width, &height)) {
            area = (double)width * (double)height;
        }

        double score = area + (builtIn ? 0.0 : 1e12);
        if (score > bestScore) {
            bestScore = score;
            bestIndex = i;
        }
    }

    return CFArrayGetValueAtIndex(devices, bestIndex);
}

static void resolveCmZones(MTDeviceRef device) {
    int32_t width = 0;
    int32_t height = 0;
    bool hasDims = getSurfaceDimensions(device, &width, &height);

    if (!hasDims &&
        (gOptions.hasLeftCm || gOptions.hasRightCm || gOptions.hasTopCm || gOptions.hasBottomCm)) {
        fprintf(stderr, "Cannot use --*-cm options because the device surface size is unknown.\n");
        exit(4);
    }

    double widthCm = (double)width / 1000.0;
    double heightCm = (double)height / 1000.0;

    if (gOptions.hasLeftCm) gOptions.leftNorm = clamp01(gOptions.leftCm / widthCm);
    if (gOptions.hasRightCm) gOptions.rightNorm = clamp01(gOptions.rightCm / widthCm);
    if (gOptions.hasTopCm) gOptions.topNorm = clamp01(gOptions.topCm / heightCm);
    if (gOptions.hasBottomCm) gOptions.bottomNorm = clamp01(gOptions.bottomCm / heightCm);

    if (hasDims) {
        fprintf(stderr,
                "Selected surface %.2fcm x %.2fcm. Dead zones: left %.2fcm, right %.2fcm, top %.2fcm, bottom %.2fcm.\n",
                widthCm,
                heightCm,
                gOptions.leftNorm * widthCm,
                gOptions.rightNorm * widthCm,
                gOptions.topNorm * heightCm,
                gOptions.bottomNorm * heightCm);
    } else {
        fprintf(stderr,
                "Selected surface size unknown. Dead zones: left %.1f%%, right %.1f%%, top %.1f%%, bottom %.1f%%.\n",
                gOptions.leftNorm * 100.0,
                gOptions.rightNorm * 100.0,
                gOptions.topNorm * 100.0,
                gOptions.bottomNorm * 100.0);
    }
}

static bool isContactState(int32_t state, float zTotal) {
    if (state == 3 || state == 4 || state == 5) {
        return true;
    }
    return zTotal > 0.001f;
}

static bool isReleaseState(int32_t state, float zTotal) {
    if (state == 6 || state == 7) {
        return true;
    }
    return zTotal <= 0.001f;
}

static double normalizedX(MTTouch *touch) {
    double x = clamp01((double)touch->normalized.position.x);
    return gOptions.invertX ? 1.0 - x : x;
}

static double normalizedY(MTTouch *touch) {
    double y = clamp01((double)touch->normalized.position.y);
    return gOptions.invertY ? 1.0 - y : y;
}

static bool isDeadZone(double x, double y) {
    if (x <= gOptions.leftNorm) return true;
    if (x >= 1.0 - gOptions.rightNorm) return true;
    if (y <= gOptions.bottomNorm) return true;
    if (y >= 1.0 - gOptions.topNorm) return true;
    return false;
}

static TouchSlot *findTouchSlot(int32_t pathIndex) {
    for (size_t i = 0; i < sizeof(gTouches) / sizeof(gTouches[0]); i++) {
        if (gTouches[i].present && gTouches[i].pathIndex == pathIndex) {
            return &gTouches[i];
        }
    }
    return NULL;
}

static TouchSlot *allocateTouchSlot(int32_t pathIndex) {
    TouchSlot *slot = findTouchSlot(pathIndex);
    if (slot) {
        return slot;
    }

    for (size_t i = 0; i < sizeof(gTouches) / sizeof(gTouches[0]); i++) {
        if (!gTouches[i].present) {
            gTouches[i].present = true;
            gTouches[i].pathIndex = pathIndex;
            gTouches[i].startedDead = false;
            gTouches[i].x = 0.0;
            gTouches[i].y = 0.0;
            gTouches[i].lastSeenMs = 0;
            return &gTouches[i];
        }
    }
    return NULL;
}

static void clearTouchSlot(int32_t pathIndex) {
    TouchSlot *slot = findTouchSlot(pathIndex);
    if (slot) {
        memset(slot, 0, sizeof(*slot));
    }
}

static void printFrameLog(uint64_t now, int32_t touchCount, unsigned active, unsigned dead, bool blocking) {
    static uint64_t lastLog = 0;
    if (!gOptions.verbose) {
        return;
    }
    if (now - lastLog < 1000) {
        return;
    }
    lastLog = now;

    unsigned suppressed = atomic_exchange(&gSuppressedEvents, 0);
    unsigned blockedFrames = atomic_exchange(&gBlockedFrames, 0);
    fprintf(stderr,
            "touches=%d active=%u dead-start=%u blocking=%s suppressed/s=%u blockedFrames/s=%u\n",
            touchCount,
            active,
            dead,
            blocking ? "yes" : "no",
            suppressed,
            blockedFrames);
}

static void contactFrameCallback(MTDeviceRef device,
                                 MTTouch *touches,
                                 int32_t touchCount,
                                 double timestamp,
                                 int32_t frame) {
    (void)device;
    (void)timestamp;
    (void)frame;

    uint64_t now = nowMs();

    for (size_t i = 0; i < sizeof(gTouches) / sizeof(gTouches[0]); i++) {
        if (gTouches[i].present && now - gTouches[i].lastSeenMs > 2000) {
            memset(&gTouches[i], 0, sizeof(gTouches[i]));
        }
    }

    for (int32_t i = 0; i < touchCount; i++) {
        MTTouch *touch = &touches[i];
        double x = normalizedX(touch);
        double y = normalizedY(touch);

        if (isReleaseState(touch->state, touch->zTotal)) {
            clearTouchSlot(touch->pathIndex);
            continue;
        }

        if (!isContactState(touch->state, touch->zTotal)) {
            continue;
        }

        TouchSlot *slot = allocateTouchSlot(touch->pathIndex);
        if (!slot) {
            continue;
        }

        bool newTouch = slot->lastSeenMs == 0;
        if (newTouch) {
            slot->startedDead = isDeadZone(x, y);
            if (gOptions.monitorOnly || gOptions.verbose) {
                fprintf(stderr,
                        "touch start path=%d state=%d x=%.3f y=%.3f dead=%s\n",
                        touch->pathIndex,
                        touch->state,
                        x,
                        y,
                        slot->startedDead ? "yes" : "no");
            }
        }

        slot->x = x;
        slot->y = y;
        slot->lastSeenMs = now;
    }

    unsigned active = 0;
    unsigned dead = 0;
    for (size_t i = 0; i < sizeof(gTouches) / sizeof(gTouches[0]); i++) {
        if (gTouches[i].present && now - gTouches[i].lastSeenMs <= 250) {
            active++;
            if (gTouches[i].startedDead) {
                dead++;
            }
        }
    }

    bool blocking = false;
    if (dead > 0) {
        if (gOptions.policy == PolicyAnyDead) {
            blocking = true;
        } else {
            blocking = (dead == active);
        }
    }

    atomic_store(&gActiveTouches, active);
    if (blocking) {
        atomic_store(&gBlockUntilMs, now + (uint64_t)gOptions.graceMs);
        atomic_fetch_add(&gBlockedFrames, 1);
    }

    printFrameLog(now, touchCount, active, dead, blocking);
}

static bool isSuppressibleEvent(CGEventType type) {
    switch (type) {
        case kCGEventLeftMouseDown:
        case kCGEventLeftMouseUp:
        case kCGEventRightMouseDown:
        case kCGEventRightMouseUp:
        case kCGEventMouseMoved:
        case kCGEventLeftMouseDragged:
        case kCGEventRightMouseDragged:
        case kCGEventOtherMouseDown:
        case kCGEventOtherMouseUp:
        case kCGEventOtherMouseDragged:
        case kCGEventScrollWheel:
            return true;
        default:
            return false;
    }
}

static CGEventRef eventTapCallback(CGEventTapProxy proxy,
                                   CGEventType type,
                                   CGEventRef event,
                                   void *userInfo) {
    (void)proxy;
    (void)userInfo;

    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        if (gEventTap) {
            CGEventTapEnable(gEventTap, true);
        }
        return event;
    }

    if (!isSuppressibleEvent(type)) {
        return event;
    }

    uint64_t until = atomic_load(&gBlockUntilMs);
    if (nowMs() <= until) {
        atomic_fetch_add(&gSuppressedEvents, 1);
        return NULL;
    }

    return event;
}

static void signalHandler(int sig) {
    (void)sig;
    gShouldStop = 1;
    CFRunLoopStop(CFRunLoopGetMain());
}

static void keepAliveTimerCallback(CFRunLoopTimerRef timer, void *info) {
    (void)timer;
    (void)info;
}

static void requestAccessibilityPrompt(void) {
    const void *keys[] = { kAXTrustedCheckOptionPrompt };
    const void *values[] = { kCFBooleanTrue };
    CFDictionaryRef options = CFDictionaryCreate(kCFAllocatorDefault,
                                                 keys,
                                                 values,
                                                 1,
                                                 &kCFTypeDictionaryKeyCallBacks,
                                                 &kCFTypeDictionaryValueCallBacks);
    bool trusted = AXIsProcessTrustedWithOptions(options);
    CFRelease(options);

    if (!trusted) {
        fprintf(stderr,
                "Accessibility permission is not granted yet. macOS may show a prompt.\n"
                "If the event tap fails, enable this binary or Terminal in:\n"
                "System Settings > Privacy & Security > Accessibility.\n");
    }
}

static void createEventTap(void) {
    CGEventMask mask =
        CGEventMaskBit(kCGEventLeftMouseDown) |
        CGEventMaskBit(kCGEventLeftMouseUp) |
        CGEventMaskBit(kCGEventRightMouseDown) |
        CGEventMaskBit(kCGEventRightMouseUp) |
        CGEventMaskBit(kCGEventMouseMoved) |
        CGEventMaskBit(kCGEventLeftMouseDragged) |
        CGEventMaskBit(kCGEventRightMouseDragged) |
        CGEventMaskBit(kCGEventOtherMouseDown) |
        CGEventMaskBit(kCGEventOtherMouseUp) |
        CGEventMaskBit(kCGEventOtherMouseDragged) |
        CGEventMaskBit(kCGEventScrollWheel);

    gEventTap = CGEventTapCreate(kCGHIDEventTap,
                                 kCGHeadInsertEventTap,
                                 kCGEventTapOptionDefault,
                                 mask,
                                 eventTapCallback,
                                 NULL);

    if (!gEventTap) {
        fprintf(stderr,
                "Could not create HID event tap. Grant Accessibility permission and try again.\n");
        exit(5);
    }

    CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, gEventTap, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
    CFRelease(source);
    CGEventTapEnable(gEventTap, true);
}

static void printSelectedSummary(void) {
    fprintf(stderr,
            "Policy=%s, grace=%dms, mode=%s. Press Ctrl-C to stop.\n",
            gOptions.policy == PolicyAllDead ? "all" : "any",
            gOptions.graceMs,
            gOptions.monitorOnly ? "monitor" : "filter");
    fprintf(stderr,
            "Dead zone normalized: left=%.3f right=%.3f top=%.3f bottom=%.3f%s%s\n",
            gOptions.leftNorm,
            gOptions.rightNorm,
            gOptions.topNorm,
            gOptions.bottomNorm,
            gOptions.invertX ? " invertX" : "",
            gOptions.invertY ? " invertY" : "");
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (!parseArgs(argc, argv)) {
            printUsage(argv[0]);
            return 1;
        }

        signal(SIGINT, signalHandler);
        signal(SIGTERM, signalHandler);

        loadMultitouchAPI();
        CFArrayRef devices = gMT.createList();
        if (!devices) {
            fprintf(stderr, "MTDeviceCreateList returned NULL.\n");
            return 3;
        }

        CFIndex count = CFArrayGetCount(devices);
        if (gOptions.listDevices) {
            for (CFIndex i = 0; i < count; i++) {
                printDevice((int)i, CFArrayGetValueAtIndex(devices, i));
            }
            return 0;
        }

        gSelectedDevice = chooseDevice(devices);
        fprintf(stderr, "Selected multitouch device:\n");
        printDevice((int)CFArrayGetFirstIndexOfValue(devices,
                                                     CFRangeMake(0, CFArrayGetCount(devices)),
                                                     gSelectedDevice),
                    gSelectedDevice);
        resolveCmZones(gSelectedDevice);
        printSelectedSummary();

        gMT.registerContactFrame(gSelectedDevice, contactFrameCallback);
        int startResult = gMT.start(gSelectedDevice, 0);
        if (startResult != 0) {
            fprintf(stderr, "MTDeviceStart returned %d. Continuing in case callbacks still arrive.\n", startResult);
        }

        if (!gOptions.monitorOnly) {
            requestAccessibilityPrompt();
            createEventTap();
        }

        CFRunLoopTimerRef keepAliveTimer =
            CFRunLoopTimerCreate(kCFAllocatorDefault,
                                 CFAbsoluteTimeGetCurrent() + 3600.0,
                                 3600.0,
                                 0,
                                 0,
                                 keepAliveTimerCallback,
                                 NULL);
        CFRunLoopAddTimer(CFRunLoopGetMain(), keepAliveTimer, kCFRunLoopCommonModes);

        CFRunLoopRun();

        CFRunLoopRemoveTimer(CFRunLoopGetMain(), keepAliveTimer, kCFRunLoopCommonModes);
        CFRelease(keepAliveTimer);

        if (gSelectedDevice) {
            gMT.unregisterContactFrame(gSelectedDevice, contactFrameCallback);
            gMT.stop(gSelectedDevice);
        }

        if (gEventTap) {
            CFRelease(gEventTap);
        }

        fprintf(stderr, "Stopped.\n");
        return gShouldStop ? 0 : 0;
    }
}
