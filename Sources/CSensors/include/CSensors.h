#ifndef TEMPBAR_SENSORS_H
#define TEMPBAR_SENSORS_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    char *name;
    double celsius;
    int group; /* 0 = CPU, 1 = GPU */
} TBTSensor;

/* Returns a malloc'd array of matching sensors, or NULL when none are found.
   Free the result with tbt_free_sensors(). */
TBTSensor *tbt_read_sensors(int *count);

void tbt_free_sensors(TBTSensor *sensors, int count);

#ifdef __cplusplus
}
#endif

#endif /* TEMPBAR_SENSORS_H */
