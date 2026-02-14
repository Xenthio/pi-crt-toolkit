/*
 * crt-setmode - DRM mode setter for Pi CRT Toolkit
 * 
 * Sets a display mode on a DRM connector and runs as a daemon
 * to hold the mode (required on KMS where modes revert when master is released).
 *
 * Usage: crt-setmode <connector_id> <mode> [tv_norm] [daemon]
 *   mode: 720x240, 720x480i, 720x288, 720x576i
 *   tv_norm: 0=NTSC, 3=PAL (optional)
 *   daemon: keep running to hold the mode
 *
 * Signal handling (daemon mode):
 *   SIGUSR1 + /tmp/crt-tvnorm file: Re-read TV norm from file and apply
 *   SIGUSR2 + /tmp/crt-margins file: Re-read margins from file and apply
 *   SIGTERM/SIGINT: Exit cleanly
 * 
 * Compile: gcc -o crt-setmode crt-setmode.c -ldrm -I/usr/include/libdrm
 */

#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <string.h>
#include <xf86drm.h>
#include <xf86drmMode.h>

static volatile int running = 1;
static volatile int reload_tvnorm = 0;
static volatile int reload_margins = 0;
static int g_fd = -1;
static uint32_t g_conn_id = 0;

#define TV_NORM_FILE "/tmp/crt-tvnorm"
#define MARGINS_FILE "/tmp/crt-margins"

void sighandler(int sig) {
    if (sig == SIGUSR1) {
        reload_tvnorm = 1;
    } else if (sig == SIGUSR2) {
        reload_margins = 1;
    } else {
        running = 0;
    }
}

// Find and set the "TV mode" property on a connector
int set_tv_mode_property(int fd, uint32_t conn_id, int tv_norm) {
    drmModeObjectProperties *props = drmModeObjectGetProperties(fd, conn_id, DRM_MODE_OBJECT_CONNECTOR);
    if (!props) {
        fprintf(stderr, "Failed to get connector properties\n");
        return -1;
    }
    
    int found = 0;
    for (uint32_t i = 0; i < props->count_props; i++) {
        drmModePropertyRes *prop = drmModeGetProperty(fd, props->props[i]);
        if (!prop) continue;
        
        if (strcmp(prop->name, "TV mode") == 0) {
            int ret = drmModeObjectSetProperty(fd, conn_id, DRM_MODE_OBJECT_CONNECTOR, 
                                               prop->prop_id, tv_norm);
            if (ret == 0) {
                printf("TV mode set to %d\n", tv_norm);
                found = 1;
            } else {
                fprintf(stderr, "Failed to set TV mode property\n");
            }
            drmModeFreeProperty(prop);
            break;
        }
        drmModeFreeProperty(prop);
    }
    
    drmModeFreeObjectProperties(props);
    return found ? 0 : -1;
}

// Read TV norm from file
int read_tvnorm_file() {
    FILE *f = fopen(TV_NORM_FILE, "r");
    if (!f) return -1;
    
    int norm = -1;
    fscanf(f, "%d", &norm);
    fclose(f);
    return norm;
}

// Set a named property on a connector
int set_connector_property(int fd, uint32_t conn_id, const char *prop_name, uint64_t value) {
    drmModeObjectProperties *props = drmModeObjectGetProperties(fd, conn_id, DRM_MODE_OBJECT_CONNECTOR);
    if (!props) return -1;
    
    int found = 0;
    for (uint32_t i = 0; i < props->count_props; i++) {
        drmModePropertyRes *prop = drmModeGetProperty(fd, props->props[i]);
        if (!prop) continue;
        
        if (strcmp(prop->name, prop_name) == 0) {
            int ret = drmModeObjectSetProperty(fd, conn_id, DRM_MODE_OBJECT_CONNECTOR, 
                                               prop->prop_id, value);
            if (ret == 0) {
                found = 1;
            }
            drmModeFreeProperty(prop);
            break;
        }
        drmModeFreeProperty(prop);
    }
    
    drmModeFreeObjectProperties(props);
    return found ? 0 : -1;
}

// Read and apply margins from file
// File format: left right top bottom (space-separated integers 0-100)
int apply_margins_from_file(int fd, uint32_t conn_id) {
    FILE *f = fopen(MARGINS_FILE, "r");
    if (!f) return -1;
    
    int left = 0, right = 0, top = 0, bottom = 0;
    if (fscanf(f, "%d %d %d %d", &left, &right, &top, &bottom) != 4) {
        fclose(f);
        return -1;
    }
    fclose(f);
    
    printf("Setting margins: L=%d R=%d T=%d B=%d\n", left, right, top, bottom);
    
    set_connector_property(fd, conn_id, "left margin", left);
    set_connector_property(fd, conn_id, "right margin", right);
    set_connector_property(fd, conn_id, "top margin", top);
    set_connector_property(fd, conn_id, "bottom margin", bottom);
    
    return 0;
}

int main(int argc, char *argv[]) {
    if (argc < 3) {
        printf("Usage: %s <connector_id> <mode> [tv_norm] [daemon]\n", argv[0]);
        printf("  mode: 720x240, 720x480i, 720x288, 720x576i\n");
        printf("  tv_norm: 0=NTSC, 3=PAL (optional, default from mode)\n");
        printf("  daemon: keep running to hold the mode\n");
        printf("\nIn daemon mode, send SIGUSR1 to reload TV norm from %s\n", TV_NORM_FILE);
        return 1;
    }
    
    int conn_id = atoi(argv[1]);
    char *mode_name = argv[2];
    int tv_norm = -1;  // Auto-detect from mode
    int daemon_mode = 0;
    
    // Parse optional args
    for (int i = 3; i < argc; i++) {
        if (strcmp(argv[i], "daemon") == 0) {
            daemon_mode = 1;
        } else if (argv[i][0] >= '0' && argv[i][0] <= '9') {
            tv_norm = atoi(argv[i]);
        }
    }
    
    // Auto-detect TV norm from mode name
    if (tv_norm < 0) {
        if (strstr(mode_name, "576") || strstr(mode_name, "288")) {
            tv_norm = 3;  // PAL
        } else {
            tv_norm = 0;  // NTSC
        }
    }
    
    g_conn_id = conn_id;
    
    // Try card1 first (Pi 4 with vc4), fall back to card0
    int fd = open("/dev/dri/card1", O_RDWR);
    if (fd < 0) {
        fd = open("/dev/dri/card0", O_RDWR);
        if (fd < 0) {
            perror("open /dev/dri/card*");
            return 1;
        }
    }
    g_fd = fd;
    
    drmModeRes *res = drmModeGetResources(fd);
    if (!res) {
        perror("drmModeGetResources");
        close(fd);
        return 1;
    }
    
    // Find the connector
    drmModeConnector *conn = drmModeGetConnector(fd, conn_id);
    if (!conn) {
        fprintf(stderr, "Connector %d not found\n", conn_id);
        drmModeFreeResources(res);
        close(fd);
        return 1;
    }
    
    // Find the requested mode
    drmModeModeInfo *mode = NULL;
    for (int i = 0; i < conn->count_modes; i++) {
        if (strcmp(conn->modes[i].name, mode_name) == 0) {
            mode = &conn->modes[i];
            break;
        }
    }
    
    if (!mode) {
        fprintf(stderr, "Mode '%s' not found. Available modes:\n", mode_name);
        for (int i = 0; i < conn->count_modes; i++) {
            fprintf(stderr, "  %s @ %dHz\n", conn->modes[i].name, conn->modes[i].vrefresh);
        }
        drmModeFreeConnector(conn);
        drmModeFreeResources(res);
        close(fd);
        return 1;
    }
    
    printf("Setting mode %s on connector %d (TV norm: %d)\n", mode_name, conn_id, tv_norm);
    
    // Set TV norm BEFORE mode switch (required for PAL modes)
    set_tv_mode_property(fd, conn_id, tv_norm);
    
    // Get encoder to find CRTC
    drmModeEncoder *enc = drmModeGetEncoder(fd, conn->encoder_id);
    if (!enc) {
        for (int i = 0; i < conn->count_encoders; i++) {
            enc = drmModeGetEncoder(fd, conn->encoders[i]);
            if (enc) break;
        }
    }
    
    if (!enc) {
        fprintf(stderr, "No encoder found for connector\n");
        drmModeFreeConnector(conn);
        drmModeFreeResources(res);
        close(fd);
        return 1;
    }
    
    uint32_t crtc_id = enc->crtc_id;
    
    if (!crtc_id) {
        for (int i = 0; i < res->count_crtcs; i++) {
            if (enc->possible_crtcs & (1 << i)) {
                crtc_id = res->crtcs[i];
                break;
            }
        }
    }
    
    drmModeFreeEncoder(enc);
    
    if (!crtc_id) {
        fprintf(stderr, "No CRTC available\n");
        drmModeFreeConnector(conn);
        drmModeFreeResources(res);
        close(fd);
        return 1;
    }
    
    // Set the mode
    int ret = drmModeSetCrtc(fd, crtc_id, -1, 0, 0, (uint32_t*)&conn_id, 1, mode);
    if (ret) {
        perror("drmModeSetCrtc");
        drmModeFreeConnector(conn);
        drmModeFreeResources(res);
        close(fd);
        return 1;
    }
    
    printf("Mode set successfully!\n");
    
    drmModeFreeConnector(conn);
    drmModeFreeResources(res);
    
    if (daemon_mode) {
        // Daemonize
        pid_t pid = fork();
        if (pid > 0) {
            // Parent exits, print child PID
            printf("%d\n", pid);
            close(fd);
            return 0;
        }
        if (pid < 0) {
            perror("fork");
            close(fd);
            return 1;
        }
        
        // Child becomes session leader
        setsid();
        
        // Write PID file
        FILE *pf = fopen("/tmp/crt-setmode.pid", "w");
        if (pf) {
            fprintf(pf, "%d\n", getpid());
            fclose(pf);
        }
        
        signal(SIGINT, sighandler);
        signal(SIGTERM, sighandler);
        signal(SIGUSR1, sighandler);
        signal(SIGUSR2, sighandler);
        
        // Keep running to hold DRM master
        while (running) {
            sleep(1);
            
            // Check if we need to reload TV norm
            if (reload_tvnorm) {
                reload_tvnorm = 0;
                int new_norm = read_tvnorm_file();
                if (new_norm >= 0) {
                    set_tv_mode_property(fd, conn_id, new_norm);
                }
            }
            
            // Check if we need to reload margins
            if (reload_margins) {
                reload_margins = 0;
                apply_margins_from_file(fd, conn_id);
            }
        }
    }
    
    close(fd);
    return 0;
}
