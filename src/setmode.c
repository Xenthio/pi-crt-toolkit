/*
 * setmode - DRM mode setter for Pi CRT Toolkit
 * 
 * Sets a display mode on a DRM connector and runs as a daemon to hold the mode.
 * Exits gracefully when another app takes DRM master (e.g., RetroArch, ES).
 *
 * Usage: setmode <connector_id> <mode>
 * 
 * Compile: gcc -o setmode setmode.c -ldrm -I/usr/include/libdrm
 */

#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <string.h>
#include <errno.h>
#include <xf86drm.h>
#include <xf86drmMode.h>

static volatile int running = 1;
static int drm_fd = -1;

void sighandler(int sig) {
    running = 0;
}

// Check if we still have DRM master
int check_drm_master(int fd) {
    // Try to get resources - fails if we lost master
    drmModeRes *res = drmModeGetResources(fd);
    if (!res) {
        return 0; // Lost master
    }
    drmModeFreeResources(res);
    return 1; // Still have master
}

int main(int argc, char *argv[]) {
    if (argc < 3) {
        printf("Usage: %s <connector_id> <mode>\n", argv[0]);
        printf("  mode: 720x240, 720x480i, 720x288, 720x576i\n");
        printf("\n");
        printf("Runs as daemon and holds DRM master to keep the mode.\n");
        printf("Exits gracefully when another app takes DRM master.\n");
        return 1;
    }
    
    int conn_id = atoi(argv[1]);
    char *mode_name = argv[2];
    
    // Try card1 first (Pi 4 with vc4), fall back to card0
    drm_fd = open("/dev/dri/card1", O_RDWR);
    if (drm_fd < 0) {
        drm_fd = open("/dev/dri/card0", O_RDWR);
        if (drm_fd < 0) {
            perror("open /dev/dri/card*");
            return 1;
        }
    }
    
    drmModeRes *res = drmModeGetResources(drm_fd);
    if (!res) {
        perror("drmModeGetResources");
        close(drm_fd);
        return 1;
    }
    
    // Find the connector
    drmModeConnector *conn = drmModeGetConnector(drm_fd, conn_id);
    if (!conn) {
        fprintf(stderr, "Connector %d not found\n", conn_id);
        drmModeFreeResources(res);
        close(drm_fd);
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
        close(drm_fd);
        return 1;
    }
    
    // Get encoder to find CRTC
    drmModeEncoder *enc = drmModeGetEncoder(drm_fd, conn->encoder_id);
    if (!enc) {
        // Try to find a valid encoder
        for (int i = 0; i < conn->count_encoders; i++) {
            enc = drmModeGetEncoder(drm_fd, conn->encoders[i]);
            if (enc) break;
        }
    }
    
    if (!enc) {
        fprintf(stderr, "No encoder found for connector\n");
        drmModeFreeConnector(conn);
        drmModeFreeResources(res);
        close(drm_fd);
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
        close(drm_fd);
        return 1;
    }
    
    // Set the mode (fb_id -1 keeps current framebuffer)
    int ret = drmModeSetCrtc(drm_fd, crtc_id, -1, 0, 0, (uint32_t*)&conn_id, 1, mode);
    if (ret) {
        perror("drmModeSetCrtc");
        drmModeFreeConnector(conn);
        drmModeFreeResources(res);
        close(drm_fd);
        return 1;
    }
    
    printf("Mode set successfully!\n");
    
    // Try to drop master while keeping the mode
    // This might allow the mode to persist while letting other apps use DRM
    drmDropMaster(drm_fd);
    printf("Dropped DRM master\n");
    
    drmModeFreeConnector(conn);
    drmModeFreeResources(res);
    
    // Keep fd open for a moment to see if mode persists
    sleep(1);
    
    close(drm_fd);
    return 0;
}
