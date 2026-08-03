#ifndef VOXFLOW_QWEN_WINDOWS_UNISTD_H
#define VOXFLOW_QWEN_WINDOWS_UNISTD_H

#include <io.h>
#include <sys/stat.h>

#ifndef _SC_NPROCESSORS_ONLN
#define _SC_NPROCESSORS_ONLN 1
#endif

#define open _open
#define close _close
#define fstat _fstat64
#define stat _stat64

long sysconf(int name);

#endif /* VOXFLOW_QWEN_WINDOWS_UNISTD_H */
