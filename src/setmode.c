/*
 * setmode - DRM mode setter for Pi CRT Toolkit
 * 
 * Sets a display mode on a DRM connector and optionally runs as a daemon
 * to hold the mode (required on KMS where modes revert when master is released).
 *
 * Usage: setmode <connector_id> <mode> [daemon]
 * 
 * Compile: gcc -o setmode setmode.c -ldrm -I/usr/include/libdrm
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

void sighandler(int sig) {
    running = 0;
}

int main(int argc, char *argv[]) {
    if (argc < 3) {
        printf("Usage: %s <connector_id> <mode> [daemon]\n", argv[0]);
        printf("  mode: 720x240, 720x480i, 720x288, 720x576i\n");
        printf("  daemon: keep running to hold the mode\n");
        return 1;
    }
    
    int conn_id = atoi(argv[1]);
    char *mode_name = argv[2];
    int daemon_mode = (argc > 3 && strcmp(argv[3], "daemon") == 0);
    
    // Try card1 first (Pi 4 with vc4), fall back to card0
    int fd = open("/dev/dri/card1", O_RDWR);
    if (fd < 0) {
        fd = open("/dev/dri/card0", O_RDWR);
        if (fd < 0) {
            perror("open /dev/dri/card*");
            return 1;
        }
    }
    
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
    
    printf("Setting mode %s on connector %d\n", mode_name, conn_id);
    
    // Get encoder to find CRTC
    drmModeEncoder *enc = drmModeGetEncoder(fd, conn->encoder_id);
    if (!enc) {
        // Try to find a valid encoder
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
    
    // If no CRTC assigned, find one from possible CRTCs
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
    
    // Set the mode (fb_id -1 keeps current framebuffer)
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
        if (fork() > 0) {
            // Parent exits
            close(fd);
            return 0;
        }
        
        // Child becomes session leader
        setsid();
        
        printf("Running as daemon (kill to release mode)...\n");
        signal(SIGINT, sighandler);
        signal(SIGTERM, sighandler);
        
        // Keep running to hold DRM master
        while (running) {
            sleep(1);
        }
        
        printf("Daemon exiting...\n");
    }
    
    close(fd);
    return 0;
}
