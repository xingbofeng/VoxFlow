#ifndef VOXFLOW_QWEN_WINDOWS_SYS_TIME_H
#define VOXFLOW_QWEN_WINDOWS_SYS_TIME_H

struct timeval {
    long tv_sec;
    long tv_usec;
};

int gettimeofday(struct timeval *value, void *timezone_ignored);

#endif /* VOXFLOW_QWEN_WINDOWS_SYS_TIME_H */
