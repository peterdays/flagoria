/* SIGTERM handler for a dedicated server. Godot 4.7 does not deliver
 * SIGTERM to scripts. The library may load with the project; the handler
 * arms only when this process was started with --server. It writes one
 * byte to /tmp/flagoria-server-quit-<pid>. The game then closes ENet and
 * exits 0. A GUI launch keeps the default SIGTERM behavior.
 */
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>

static int quit_fd = -1;

static void on_sigterm(int sig) {
	(void)sig;
	if (quit_fd >= 0) {
		const char mark = '1';
		ssize_t wrote = write(quit_fd, &mark, 1);
		(void)wrote;
	}
}

static int cmdline_has_server(void) {
	FILE *cmdline = fopen("/proc/self/cmdline", "rb");
	if (cmdline == NULL) {
		return 0;
	}
	char buf[4096];
	size_t n = fread(buf, 1, sizeof(buf), cmdline);
	fclose(cmdline);
	size_t i = 0;
	while (i < n) {
		if (strcmp(buf + i, "--server") == 0) {
			return 1;
		}
		i += strlen(buf + i) + 1;
	}
	return 0;
}

static void install_handler(void) {
	/* Only a real `-- --server` process. A GUI launch must keep the
	 * default SIGTERM behavior. */
	if (!cmdline_has_server()) {
		return;
	}
	char path[64];
	snprintf(path, sizeof(path), "/tmp/flagoria-server-quit-%d", (int)getpid());
	quit_fd = open(path, O_CREAT | O_WRONLY | O_TRUNC | O_CLOEXEC, 0600);
	if (quit_fd < 0) {
		return;
	}
	struct sigaction action;
	memset(&action, 0, sizeof(action));
	action.sa_handler = on_sigterm;
	sigemptyset(&action.sa_mask);
	sigaction(SIGTERM, &action, NULL);
}

typedef uint8_t GDExtensionBool;
typedef void *GDExtensionClassLibraryPtr;
typedef enum {
	GDEXTENSION_INITIALIZATION_CORE,
	GDEXTENSION_INITIALIZATION_SERVERS,
	GDEXTENSION_INITIALIZATION_SCENE,
	GDEXTENSION_INITIALIZATION_EDITOR,
	GDEXTENSION_MAX_INITIALIZATION_LEVEL,
} GDExtensionInitializationLevel;
typedef void (*GDExtensionInitializeCallback)(void *userdata, GDExtensionInitializationLevel level);
typedef void (*GDExtensionDeinitializeCallback)(void *userdata, GDExtensionInitializationLevel level);
typedef struct {
	GDExtensionInitializationLevel minimum_initialization_level;
	void *userdata;
	GDExtensionInitializeCallback initialize;
	GDExtensionDeinitializeCallback deinitialize;
} GDExtensionInitialization;
typedef void (*GDExtensionInterfaceFunctionPtr)(void);
typedef GDExtensionInterfaceFunctionPtr (*GDExtensionInterfaceGetProcAddress)(const char *name);

static void init_level(void *userdata, GDExtensionInitializationLevel level) {
	(void)userdata;
	(void)level;
}
static void deinit_level(void *userdata, GDExtensionInitializationLevel level) {
	(void)userdata;
	(void)level;
}

__attribute__((visibility("default")))
GDExtensionBool server_shutdown_init(GDExtensionInterfaceGetProcAddress get_proc, GDExtensionClassLibraryPtr library, GDExtensionInitialization *init) {
	(void)get_proc;
	(void)library;
	install_handler();
	init->minimum_initialization_level = GDEXTENSION_INITIALIZATION_CORE;
	init->userdata = NULL;
	init->initialize = init_level;
	init->deinitialize = deinit_level;
	return 1;
}
