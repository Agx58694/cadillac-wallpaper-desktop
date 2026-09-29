#include <errno.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#if defined(__arm64__)
#define PACKAGER_NAME "cadillac_wallpaper_packager_arm64"
#elif defined(__x86_64__)
#define PACKAGER_NAME "cadillac_wallpaper_packager_x86_64"
#else
#error Unsupported macOS architecture
#endif

int main(int argc, char *argv[]) {
  (void)argc;
  uint32_t path_size = PATH_MAX;
  char path_buffer[PATH_MAX];
  char *launcher_path = path_buffer;
  if (_NSGetExecutablePath(launcher_path, &path_size) != 0) {
    launcher_path = malloc(path_size);
    if (launcher_path == NULL ||
        _NSGetExecutablePath(launcher_path, &path_size) != 0) {
      fputs("Cannot resolve packager launcher path\n", stderr);
      return 1;
    }
  }

  char *last_slash = strrchr(launcher_path, '/');
  if (last_slash == NULL) {
    fputs("Invalid packager launcher path\n", stderr);
    return 1;
  }
  size_t directory_length = (size_t)(last_slash - launcher_path);
  size_t target_length = directory_length + 1 + strlen(PACKAGER_NAME) + 1;
  char *target_path = malloc(target_length);
  if (target_path == NULL) {
    fputs("Cannot allocate packager path\n", stderr);
    return 1;
  }
  snprintf(target_path, target_length, "%.*s/%s", (int)directory_length,
           launcher_path, PACKAGER_NAME);
  argv[0] = target_path;
  execv(target_path, argv);
  fprintf(stderr, "Cannot start packager runtime: %s\n", strerror(errno));
  return 1;
}
