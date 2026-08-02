#ifndef VOXFLOW_QWEN_WINDOWS_DIRENT_H
#define VOXFLOW_QWEN_WINDOWS_DIRENT_H

struct dirent {
    char d_name[1024];
};

typedef struct voxflow_windows_directory DIR;

DIR *opendir(const char *path);
struct dirent *readdir(DIR *directory);
int closedir(DIR *directory);

#endif /* VOXFLOW_QWEN_WINDOWS_DIRENT_H */
