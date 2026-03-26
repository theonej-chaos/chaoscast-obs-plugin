#pragma once

// Initialize ChaosCast vendor requests with obs-websocket v5
// Must be called from obs_module_load() after the module is set up
void chaoscast_vendor_init();

// Clean up all managed outputs before OBS shutdown
// Must be called from OBS_FRONTEND_EVENT_EXIT handler
void chaoscast_vendor_shutdown();
