// Sensor access for Apple Silicon Macs.
//
// Die temperatures are not exposed through SMC on Apple Silicon. They are
// IOHIDEventService devices, reachable through private but long-standing IOKit
// entry points. This is the same unprivileged source used by other macOS
// temperature monitors. The private symbols are resolved with dlsym so the
// project builds with Command Line Tools alone (no private headers needed).

#include "CSensors.h"

#include <CoreFoundation/CoreFoundation.h>
#include <ctype.h>
#include <dlfcn.h>
#include <math.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

typedef void *IOHIDEventSystemClientRef;
typedef void *IOHIDServiceClientRef;
typedef void *IOHIDEventRef;

typedef IOHIDEventSystemClientRef (*CreateFn)(CFAllocatorRef, int32_t, CFDictionaryRef);
typedef CFArrayRef (*CopyServicesFn)(IOHIDEventSystemClientRef);
typedef CFTypeRef (*CopyPropertyFn)(IOHIDServiceClientRef, CFStringRef);
typedef IOHIDEventRef (*CopyEventFn)(IOHIDServiceClientRef, int64_t, int32_t, int64_t);
typedef double (*GetFloatFn)(IOHIDEventRef, uint32_t);

#define kHIDEventTypeTemperature 15
#define kHIDEventFieldTemperatureLevel ((uint32_t)15 << 16)
#define kHIDEventSystemClientTypeMonitor 1

static pthread_once_t g_once = PTHREAD_ONCE_INIT;
static int g_available = 0;

static CreateFn g_create = NULL;
static CopyServicesFn g_copy_services = NULL;
static CopyPropertyFn g_copy_property = NULL;
static CopyEventFn g_copy_event = NULL;
static GetFloatFn g_get_float = NULL;

static void load_symbols(void) {
    void *handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
    if (!handle) {
        return;
    }

    g_create = (CreateFn)dlsym(handle, "IOHIDEventSystemClientCreateWithType");
    g_copy_services = (CopyServicesFn)dlsym(handle, "IOHIDEventSystemClientCopyServices");
    g_copy_property = (CopyPropertyFn)dlsym(handle, "IOHIDServiceClientCopyProperty");
    g_copy_event = (CopyEventFn)dlsym(handle, "IOHIDServiceClientCopyEvent");
    g_get_float = (GetFloatFn)dlsym(handle, "IOHIDEventGetFloatValue");

    g_available = g_create && g_copy_services && g_copy_property && g_copy_event && g_get_float;
}

/* Mirrors the grouping used by popular Apple Silicon monitors:
   PMU tdie* = CPU die, PMU tdev* = GPU die. PMU2 is a second die group. */
static int classify_sensor(const char *raw_name) {
    char name[256];
    size_t length = strlen(raw_name);
    if (length >= sizeof(name)) {
        length = sizeof(name) - 1;
    }
    for (size_t i = 0; i < length; i++) {
        name[i] = (char)tolower((unsigned char)raw_name[i]);
    }
    name[length] = '\0';

    const char *base = name;
    if (strncmp(base, "pmu2 ", 5) == 0) {
        base += 5;
    } else if (strncmp(base, "pmu ", 4) == 0) {
        base += 4;
    } else {
        base = NULL;
    }

    if (base && strncmp(base, "tdie", 4) == 0) {
        return 0;
    }
    if (base && strncmp(base, "tdev", 4) == 0) {
        return 1;
    }
    if (strstr(name, "gpu") != NULL) {
        return 1;
    }
    if (strstr(name, "cpu") != NULL && strstr(name, "temp") != NULL) {
        return 0;
    }
    return -1;
}

TBTSensor *tbt_read_sensors(int *out_count) {
    if (out_count) {
        *out_count = 0;
    }

    pthread_once(&g_once, load_symbols);
    if (!g_available) {
        return NULL;
    }

    IOHIDEventSystemClientRef client = g_create(kCFAllocatorDefault, kHIDEventSystemClientTypeMonitor, NULL);
    if (!client) {
        return NULL;
    }

    CFArrayRef services = g_copy_services(client);
    if (!services) {
        CFRelease(client);
        return NULL;
    }

    TBTSensor *result = NULL;
    int count = 0;
    int capacity = 0;
    CFIndex service_count = CFArrayGetCount(services);

    for (CFIndex index = 0; index < service_count; index++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, index);
        if (!service) {
            continue;
        }

        CFTypeRef product = g_copy_property(service, CFSTR("Product"));
        if (!product) {
            continue;
        }
        if (CFGetTypeID(product) != CFStringGetTypeID()) {
            CFRelease(product);
            continue;
        }

        char name[256];
        Boolean converted = CFStringGetCString((CFStringRef)product, name, sizeof(name), kCFStringEncodingUTF8);
        CFRelease(product);
        if (!converted) {
            continue;
        }

        int group = classify_sensor(name);
        if (group < 0) {
            continue;
        }

        IOHIDEventRef event = g_copy_event(service, kHIDEventTypeTemperature, 0, 0);
        if (!event) {
            continue;
        }
        double celsius = g_get_float(event, kHIDEventFieldTemperatureLevel);
        CFRelease(event);

        /* Some services report -1, calibration values, or zero. */
        if (!isfinite(celsius) || celsius <= 0.0 || celsius >= 130.0) {
            continue;
        }

        if (count == capacity) {
            int new_capacity = capacity == 0 ? 16 : capacity * 2;
            TBTSensor *grown = (TBTSensor *)realloc(result, sizeof(TBTSensor) * (size_t)new_capacity);
            if (!grown) {
                break;
            }
            result = grown;
            capacity = new_capacity;
        }

        char *copied_name = strdup(name);
        if (!copied_name) {
            break;
        }

        result[count].name = copied_name;
        result[count].celsius = celsius;
        result[count].group = group;
        count++;
    }

    CFRelease(services);
    CFRelease(client);

    if (count == 0) {
        free(result);
        return NULL;
    }

    if (out_count) {
        *out_count = count;
    }
    return result;
}

void tbt_free_sensors(TBTSensor *sensors, int count) {
    if (!sensors) {
        return;
    }
    for (int index = 0; index < count; index++) {
        free(sensors[index].name);
    }
    free(sensors);
}
