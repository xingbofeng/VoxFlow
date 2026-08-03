#ifndef VOXFLOW_QWEN_WINDOWS_PTHREAD_H
#define VOXFLOW_QWEN_WINDOWS_PTHREAD_H

#include <windows.h>

typedef HANDLE pthread_t;
typedef SRWLOCK pthread_mutex_t;
typedef CONDITION_VARIABLE pthread_cond_t;
typedef void *(*pthread_start_routine_t)(void *);

#define PTHREAD_MUTEX_INITIALIZER SRWLOCK_INIT
#define PTHREAD_COND_INITIALIZER CONDITION_VARIABLE_INIT

int pthread_create(
    pthread_t *thread,
    const void *attributes,
    pthread_start_routine_t start_routine,
    void *context);
int pthread_join(pthread_t thread, void **return_value);

int pthread_mutex_init(pthread_mutex_t *mutex, const void *attributes);
int pthread_mutex_destroy(pthread_mutex_t *mutex);
int pthread_mutex_lock(pthread_mutex_t *mutex);
int pthread_mutex_unlock(pthread_mutex_t *mutex);

int pthread_cond_init(pthread_cond_t *condition, const void *attributes);
int pthread_cond_destroy(pthread_cond_t *condition);
int pthread_cond_wait(pthread_cond_t *condition, pthread_mutex_t *mutex);
int pthread_cond_signal(pthread_cond_t *condition);
int pthread_cond_broadcast(pthread_cond_t *condition);

#endif /* VOXFLOW_QWEN_WINDOWS_PTHREAD_H */
