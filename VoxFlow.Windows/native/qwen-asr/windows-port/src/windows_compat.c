#include "windows-msvc.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <io.h>
#include <process.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/time.h>
#include <unistd.h>
#include <wchar.h>
#include <windows.h>

/* SRW locks and condition variables are available before the Windows 10 1809
 * minimum and provide the exact atomic release/wait operation needed by the
 * pinned upstream's small pthread surface.
 * Sources:
 * https://learn.microsoft.com/en-us/windows/win32/sync/slim-reader-writer--srw--locks
 * https://learn.microsoft.com/en-us/windows/win32/sync/condition-variables */

typedef struct {
    pthread_start_routine_t start_routine;
    void *context;
} thread_start_context_t;

static unsigned __stdcall thread_entry(void *opaque_context) {
    thread_start_context_t *start = (thread_start_context_t *)opaque_context;
    pthread_start_routine_t routine = start->start_routine;
    void *context = start->context;
    free(start);
    (void)routine(context);
    return 0;
}

int pthread_create(
    pthread_t *thread,
    const void *attributes,
    pthread_start_routine_t start_routine,
    void *context) {
    (void)attributes;
    if (thread == NULL || start_routine == NULL) return EINVAL;

    thread_start_context_t *start = (thread_start_context_t *)malloc(sizeof(*start));
    if (start == NULL) return ENOMEM;
    start->start_routine = start_routine;
    start->context = context;

    /* _beginthreadex is required for threads that call the C runtime.
     * Source: https://learn.microsoft.com/en-us/cpp/c-runtime-library/reference/beginthread-beginthreadex */
    uintptr_t handle = _beginthreadex(NULL, 0, thread_entry, start, 0, NULL);
    if (handle == 0) {
        int error = errno == 0 ? EAGAIN : errno;
        free(start);
        return error;
    }
    *thread = (HANDLE)handle;
    return 0;
}

int pthread_join(pthread_t thread, void **return_value) {
    if (thread == NULL) return EINVAL;
    DWORD wait_result = WaitForSingleObject(thread, INFINITE);
    if (wait_result != WAIT_OBJECT_0) return EINVAL;
    if (!CloseHandle(thread)) return EINVAL;
    if (return_value != NULL) *return_value = NULL;
    return 0;
}

int pthread_mutex_init(pthread_mutex_t *mutex, const void *attributes) {
    (void)attributes;
    if (mutex == NULL) return EINVAL;
    InitializeSRWLock(mutex);
    return 0;
}

int pthread_mutex_destroy(pthread_mutex_t *mutex) {
    return mutex == NULL ? EINVAL : 0;
}

int pthread_mutex_lock(pthread_mutex_t *mutex) {
    if (mutex == NULL) return EINVAL;
    AcquireSRWLockExclusive(mutex);
    return 0;
}

int pthread_mutex_unlock(pthread_mutex_t *mutex) {
    if (mutex == NULL) return EINVAL;
    ReleaseSRWLockExclusive(mutex);
    return 0;
}

int pthread_cond_init(pthread_cond_t *condition, const void *attributes) {
    (void)attributes;
    if (condition == NULL) return EINVAL;
    InitializeConditionVariable(condition);
    return 0;
}

int pthread_cond_destroy(pthread_cond_t *condition) {
    return condition == NULL ? EINVAL : 0;
}

int pthread_cond_wait(pthread_cond_t *condition, pthread_mutex_t *mutex) {
    if (condition == NULL || mutex == NULL) return EINVAL;
    if (!SleepConditionVariableSRW(condition, mutex, INFINITE, 0)) {
        DWORD error = GetLastError();
        return error == 0 ? EINVAL : (int)error;
    }
    return 0;
}

int pthread_cond_signal(pthread_cond_t *condition) {
    if (condition == NULL) return EINVAL;
    WakeConditionVariable(condition);
    return 0;
}

int pthread_cond_broadcast(pthread_cond_t *condition) {
    if (condition == NULL) return EINVAL;
    WakeAllConditionVariable(condition);
    return 0;
}

long sysconf(int name) {
    if (name != _SC_NPROCESSORS_ONLN) {
        errno = EINVAL;
        return -1;
    }
    DWORD count = GetActiveProcessorCount(ALL_PROCESSOR_GROUPS);
    return count == 0 ? 1 : (long)count;
}

int gettimeofday(struct timeval *value, void *timezone_ignored) {
    (void)timezone_ignored;
    if (value == NULL) {
        errno = EINVAL;
        return -1;
    }

    /* FILETIME counts 100 ns intervals since 1601-01-01 UTC. Windows 8 and
     * later provide the precise form used here.
     * Source: https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/nf-sysinfoapi-getsystemtimepreciseasfiletime */
    FILETIME file_time;
    ULARGE_INTEGER ticks;
    const ULONGLONG unix_epoch_ticks = 116444736000000000ULL;
    GetSystemTimePreciseAsFileTime(&file_time);
    ticks.LowPart = file_time.dwLowDateTime;
    ticks.HighPart = file_time.dwHighDateTime;
    if (ticks.QuadPart < unix_epoch_ticks) {
        errno = EINVAL;
        return -1;
    }
    ULONGLONG unix_ticks = ticks.QuadPart - unix_epoch_ticks;
    value->tv_sec = (long)(unix_ticks / 10000000ULL);
    value->tv_usec = (long)((unix_ticks % 10000000ULL) / 10ULL);
    return 0;
}

/* A mapped view remains valid after the file-mapping handle is closed. That
 * lets the unmodified upstream close its CRT descriptor immediately after
 * mmap(), while munmap() later releases the view.
 * Sources:
 * https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-createfilemappingw
 * https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-mapviewoffile */
void *mmap(
    void *requested_address,
    size_t length,
    int protection,
    int flags,
    int file_descriptor,
    long long offset) {
    (void)requested_address;
    if (length == 0 || protection != PROT_READ || flags != MAP_PRIVATE || offset < 0) {
        errno = EINVAL;
        return MAP_FAILED;
    }

    intptr_t file_handle = _get_osfhandle(file_descriptor);
    if (file_handle == -1) {
        errno = EBADF;
        return MAP_FAILED;
    }

    HANDLE mapping = CreateFileMappingW((HANDLE)file_handle, NULL, PAGE_READONLY, 0, 0, NULL);
    if (mapping == NULL) {
        errno = EACCES;
        return MAP_FAILED;
    }

    ULONGLONG unsigned_offset = (ULONGLONG)offset;
    DWORD offset_high = (DWORD)(unsigned_offset >> 32);
    DWORD offset_low = (DWORD)(unsigned_offset & 0xffffffffULL);
    void *view = MapViewOfFile(mapping, FILE_MAP_READ, offset_high, offset_low, length);
    (void)CloseHandle(mapping);
    if (view == NULL) {
        errno = EACCES;
        return MAP_FAILED;
    }
    return view;
}

int munmap(void *address, size_t length) {
    (void)length;
    if (address == NULL || address == MAP_FAILED) {
        errno = EINVAL;
        return -1;
    }
    if (!UnmapViewOfFile(address)) {
        errno = EINVAL;
        return -1;
    }
    return 0;
}

struct voxflow_windows_directory {
    HANDLE search_handle;
    WIN32_FIND_DATAW current_data;
    int return_current;
    struct dirent current_entry;
};

static wchar_t *utf8_search_pattern(const char *path) {
    if (path == NULL || path[0] == '\0') return NULL;
    int required = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, NULL, 0);
    if (required <= 0) return NULL;
    size_t capacity = (size_t)required + 2;
    wchar_t *pattern = (wchar_t *)calloc(capacity, sizeof(wchar_t));
    if (pattern == NULL) return NULL;
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, pattern, required) <= 0) {
        free(pattern);
        return NULL;
    }

    size_t length = wcslen(pattern);
    if (length > 0 && (pattern[length - 1] == L'\\' || pattern[length - 1] == L'/')) {
        pattern[length] = L'*';
        pattern[length + 1] = L'\0';
    } else {
        pattern[length] = L'\\';
        pattern[length + 1] = L'*';
        pattern[length + 2] = L'\0';
    }
    return pattern;
}

DIR *opendir(const char *path) {
    wchar_t *pattern = utf8_search_pattern(path);
    if (pattern == NULL) {
        errno = EINVAL;
        return NULL;
    }

    DIR *directory = (DIR *)calloc(1, sizeof(*directory));
    if (directory == NULL) {
        free(pattern);
        errno = ENOMEM;
        return NULL;
    }
    directory->search_handle = FindFirstFileW(pattern, &directory->current_data);
    free(pattern);
    if (directory->search_handle == INVALID_HANDLE_VALUE) {
        free(directory);
        errno = ENOENT;
        return NULL;
    }
    directory->return_current = 1;
    return directory;
}

struct dirent *readdir(DIR *directory) {
    if (directory == NULL || directory->search_handle == INVALID_HANDLE_VALUE) {
        errno = EINVAL;
        return NULL;
    }

    if (directory->return_current) {
        directory->return_current = 0;
    } else if (!FindNextFileW(directory->search_handle, &directory->current_data)) {
        DWORD error = GetLastError();
        if (error != ERROR_NO_MORE_FILES) errno = EIO;
        return NULL;
    }

    int converted = WideCharToMultiByte(
        CP_UTF8,
        WC_ERR_INVALID_CHARS,
        directory->current_data.cFileName,
        -1,
        directory->current_entry.d_name,
        (int)sizeof(directory->current_entry.d_name),
        NULL,
        NULL);
    if (converted <= 0) {
        errno = EILSEQ;
        return NULL;
    }
    return &directory->current_entry;
}

int closedir(DIR *directory) {
    if (directory == NULL) {
        errno = EINVAL;
        return -1;
    }
    BOOL closed = FindClose(directory->search_handle);
    free(directory);
    if (!closed) {
        errno = EIO;
        return -1;
    }
    return 0;
}
