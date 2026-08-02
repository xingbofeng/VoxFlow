#include "windows-msvc.h"

#include <dirent.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>
#include <windows.h>

static pthread_mutex_t shared_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t shared_condition = PTHREAD_COND_INITIALIZER;
static int shared_ready = 0;
static int shared_value = 0;

static void *worker(void *context) {
    int *expected = (int *)context;
    if (pthread_mutex_lock(&shared_mutex) != 0) return NULL;
    while (!shared_ready) {
        if (pthread_cond_wait(&shared_condition, &shared_mutex) != 0) {
            (void)pthread_mutex_unlock(&shared_mutex);
            return NULL;
        }
    }
    shared_value = *expected;
    (void)pthread_mutex_unlock(&shared_mutex);
    return NULL;
}

static int fail(const char *message) {
    fprintf(stderr, "FAIL: %s\n", message);
    return 1;
}

static int test_threads(void) {
    int expected = 42;
    pthread_t thread = NULL;
    if (pthread_create(&thread, NULL, worker, &expected) != 0) return fail("pthread_create");
    if (pthread_mutex_lock(&shared_mutex) != 0) return fail("pthread_mutex_lock");
    shared_ready = 1;
    if (pthread_cond_signal(&shared_condition) != 0) return fail("pthread_cond_signal");
    if (pthread_mutex_unlock(&shared_mutex) != 0) return fail("pthread_mutex_unlock");
    if (pthread_join(thread, NULL) != 0) return fail("pthread_join");
    if (shared_value != expected) return fail("thread did not observe signaled value");

    pthread_mutex_t dynamic_mutex;
    pthread_cond_t dynamic_condition;
    if (pthread_mutex_init(&dynamic_mutex, NULL) != 0) return fail("pthread_mutex_init");
    if (pthread_cond_init(&dynamic_condition, NULL) != 0) return fail("pthread_cond_init");
    if (pthread_cond_destroy(&dynamic_condition) != 0) return fail("pthread_cond_destroy");
    if (pthread_mutex_destroy(&dynamic_mutex) != 0) return fail("pthread_mutex_destroy");
    return 0;
}

static int test_mapping(void) {
    char path[MAX_PATH];
    char temp_directory[MAX_PATH];
    const unsigned char expected[] = {0x51, 0x57, 0x45, 0x4e};
    if (GetTempPathA(MAX_PATH, temp_directory) == 0) return fail("GetTempPathA");
    if (GetTempFileNameA(temp_directory, "vfw", 0, path) == 0) return fail("GetTempFileNameA");

    FILE *file = fopen(path, "wb");
    if (file == NULL) return fail("fopen write");
    if (fwrite(expected, 1, sizeof(expected), file) != sizeof(expected)) {
        (void)fclose(file);
        return fail("fwrite");
    }
    if (fclose(file) != 0) return fail("fclose write");

    int descriptor = open(path, O_RDONLY);
    if (descriptor < 0) return fail("open");
    struct stat metadata;
    if (fstat(descriptor, &metadata) != 0) {
        (void)close(descriptor);
        return fail("fstat");
    }
    void *view = mmap(NULL, (size_t)metadata.st_size, PROT_READ, MAP_PRIVATE, descriptor, 0);
    if (close(descriptor) != 0) return fail("close");
    if (view == MAP_FAILED) return fail("mmap");
    if (memcmp(view, expected, sizeof(expected)) != 0) {
        (void)munmap(view, sizeof(expected));
        return fail("mapped bytes");
    }
    if (munmap(view, sizeof(expected)) != 0) return fail("munmap");
    if (!DeleteFileA(path)) return fail("DeleteFileA mapping file");
    return 0;
}

static int test_directory(void) {
    char temporary_file[MAX_PATH];
    char temporary_directory[MAX_PATH];
    char child_path[MAX_PATH];
    if (GetTempPathA(MAX_PATH, temporary_directory) == 0) return fail("GetTempPathA directory");
    if (GetTempFileNameA(temporary_directory, "vfd", 0, temporary_file) == 0) return fail("GetTempFileNameA directory");
    if (!DeleteFileA(temporary_file)) return fail("DeleteFileA directory placeholder");
    if (!CreateDirectoryA(temporary_file, NULL)) return fail("CreateDirectoryA");
    if (sprintf_s(child_path, sizeof(child_path), "%s\\model-00001-of-00001.safetensors", temporary_file) < 0) {
        return fail("sprintf_s");
    }

    FILE *file = fopen(child_path, "wb");
    if (file == NULL) return fail("fopen directory child");
    if (fclose(file) != 0) return fail("fclose directory child");

    DIR *directory = opendir(temporary_file);
    if (directory == NULL) return fail("opendir");
    int found = 0;
    struct dirent *entry;
    while ((entry = readdir(directory)) != NULL) {
        if (strcmp(entry->d_name, "model-00001-of-00001.safetensors") == 0) found = 1;
    }
    if (closedir(directory) != 0) return fail("closedir");
    if (!DeleteFileA(child_path)) return fail("DeleteFileA child");
    if (!RemoveDirectoryA(temporary_file)) return fail("RemoveDirectoryA");
    if (!found) return fail("directory entry missing");
    return 0;
}

static int test_time_cpu_and_compiler_shims(void) {
    struct timeval now;
    if (gettimeofday(&now, NULL) != 0) return fail("gettimeofday");
    if (now.tv_sec <= 0 || now.tv_usec < 0 || now.tv_usec >= 1000000) return fail("timeval range");
    if (sysconf(_SC_NPROCESSORS_ONLN) < 1) return fail("sysconf CPU count");

    char *copy = strdup("qwen");
    if (copy == NULL) return fail("strdup");
    int matches = strcmp(copy, "qwen") == 0;
    free(copy);
    if (!matches) return fail("strdup bytes");
    return 0;
}

int main(void) {
    if (test_threads() != 0) return 1;
    if (test_mapping() != 0) return 1;
    if (test_directory() != 0) return 1;
    if (test_time_cpu_and_compiler_shims() != 0) return 1;
    puts("PASS: Win32 qwen-asr portability contracts");
    return 0;
}
