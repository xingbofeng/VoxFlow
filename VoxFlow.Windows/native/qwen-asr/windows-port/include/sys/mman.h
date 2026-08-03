#ifndef VOXFLOW_QWEN_WINDOWS_SYS_MMAN_H
#define VOXFLOW_QWEN_WINDOWS_SYS_MMAN_H

#include <stddef.h>

#define PROT_READ 0x1
#define MAP_PRIVATE 0x2
#define MAP_FAILED ((void *)-1)

void *mmap(
    void *requested_address,
    size_t length,
    int protection,
    int flags,
    int file_descriptor,
    long long offset);
int munmap(void *address, size_t length);

#endif /* VOXFLOW_QWEN_WINDOWS_SYS_MMAN_H */
