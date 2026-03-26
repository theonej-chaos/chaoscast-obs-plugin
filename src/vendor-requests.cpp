/*
 * vendor-requests.cpp — ChaosCast vendor request handlers for obs-websocket v5
 *
 * Registers a "chaoscast" vendor with obs-websocket so the OBS Bridge can
 * control multiple RTMP outputs via CallVendorRequest over the existing
 * WebSocket connection. Each output shares the main streaming encoder.
 *
 * Uses the official obs-websocket vendor API (obs-websocket-api.h).
 * MUST be called from obs_module_post_load() per the API docs.
 *
 * License: GPL-2.0 (same as obs-multi-rtmp)
 */

#include "pch.h"
#include "vendor-requests.h"
#include "obs-multi-rtmp.h"

#include <obs.h>
#include <obs-module.h>
#include <obs-frontend-api.h>
#include "obs.hpp"

#include <unordered_map>
#include <mutex>
#include <string>
#include <cstring>

// Override TAG from pch.h for this translation unit
#undef TAG
#define TAG "[chaoscast-vendor] "

// ── obs-websocket vendor API (from obs-websocket-api.h) ──
// We inline the necessary parts to avoid a build dependency on obs-websocket headers.

typedef void *obs_websocket_vendor;
typedef void (*obs_websocket_request_callback_function)(
    obs_data_t *request_data, obs_data_t *response_data, void *priv_data);

struct obs_websocket_request_callback {
    obs_websocket_request_callback_function callback;
    void *priv_data;
};

// Get obs-websocket's private proc_handler (NOT the global one)
static proc_handler_t *get_websocket_ph()
{
    proc_handler_t *global_ph = obs_get_proc_handler();
    if (!global_ph) return nullptr;

    calldata_t cd = {0, 0, 0, 0};
    if (!proc_handler_call(global_ph, "obs_websocket_api_get_ph", &cd)) {
        calldata_free(&cd);
        return nullptr;
    }
    proc_handler_t *ph = (proc_handler_t *)calldata_ptr(&cd, "ph");
    calldata_free(&cd);
    return ph;
}

// ── Managed Output ──
struct ManagedOutput {
    std::string name;
    std::string server;
    std::string key;
    obs_output_t *output = nullptr;
    obs_service_t *service = nullptr;
    bool running = false;
    std::string lastError;
};

static std::mutex s_mutex;
static std::unordered_map<std::string, ManagedOutput> s_outputs;

// ── Signal Handlers ──
static void on_output_started(void *data, calldata_t *)
{
    auto name = static_cast<std::string *>(data);
    std::lock_guard<std::mutex> lock(s_mutex);
    auto it = s_outputs.find(*name);
    if (it != s_outputs.end()) {
        it->second.running = true;
        it->second.lastError.clear();
        blog(LOG_INFO, TAG "%s started", name->c_str());
    }
}

static void on_output_stopped(void *data, calldata_t *params)
{
    auto name = static_cast<std::string *>(data);
    int code = calldata_int(params, "code");
    std::lock_guard<std::mutex> lock(s_mutex);
    auto it = s_outputs.find(*name);
    if (it != s_outputs.end()) {
        it->second.running = false;
        if (code != 0) {
            it->second.lastError = "Stopped with code " + std::to_string(code);
        }
        blog(LOG_INFO, TAG "%s stopped (code %d)", name->c_str(), code);
    }
}

// ── Helper: get main streaming encoder ──
static obs_encoder_t *get_main_video_encoder()
{
    OBSOutputAutoRelease stream_output = obs_frontend_get_streaming_output();
    if (!stream_output) return nullptr;
    return obs_output_get_video_encoder(stream_output);
}

static obs_encoder_t *get_main_audio_encoder()
{
    OBSOutputAutoRelease stream_output = obs_frontend_get_streaming_output();
    if (!stream_output) return nullptr;
    return obs_output_get_audio_encoder(stream_output, 0);
}

// ── add_output handler ──
static void handle_add_output(obs_data_t *request, obs_data_t *response, void *)
{
    const char *name = obs_data_get_string(request, "name");
    const char *rtmp_server = obs_data_get_string(request, "server");
    const char *rtmp_key = obs_data_get_string(request, "key");

    if (!name || !name[0]) {
        obs_data_set_bool(response, "success", false);
        obs_data_set_string(response, "error", "Missing 'name'");
        return;
    }

    std::lock_guard<std::mutex> lock(s_mutex);

    auto it = s_outputs.find(name);
    if (it != s_outputs.end()) {
        if (it->second.running) {
            obs_data_set_bool(response, "success", false);
            obs_data_set_string(response, "error", "Output is running, stop it first");
            return;
        }
        if (it->second.output) {
            obs_output_release(it->second.output);
            it->second.output = nullptr;
        }
        if (it->second.service) {
            obs_service_release(it->second.service);
            it->second.service = nullptr;
        }
        s_outputs.erase(it);
    }

    ManagedOutput mo;
    mo.name = name;
    mo.server = rtmp_server ? rtmp_server : "";
    mo.key = rtmp_key ? rtmp_key : "";
    s_outputs[name] = std::move(mo);

    blog(LOG_INFO, TAG "add_output: %s -> %s", name, rtmp_server ? rtmp_server : "(none)");
    obs_data_set_bool(response, "success", true);
}

// ── start_output handler ──
static void handle_start_output(obs_data_t *request, obs_data_t *response, void *)
{
    const char *name = obs_data_get_string(request, "name");
    if (!name || !name[0]) {
        obs_data_set_bool(response, "success", false);
        obs_data_set_string(response, "error", "Missing 'name'");
        return;
    }

    std::lock_guard<std::mutex> lock(s_mutex);

    auto it = s_outputs.find(name);
    if (it == s_outputs.end()) {
        obs_data_set_bool(response, "success", false);
        obs_data_set_string(response, "error", "Output not found. Call add_output first.");
        return;
    }

    auto &mo = it->second;
    if (mo.running) {
        obs_data_set_bool(response, "success", true);
        obs_data_set_string(response, "info", "Already running");
        return;
    }

    const char *srv = obs_data_get_string(request, "server");
    const char *key = obs_data_get_string(request, "key");
    if (srv && srv[0]) mo.server = srv;
    if (key && key[0]) mo.key = key;

    if (mo.server.empty() || mo.key.empty()) {
        obs_data_set_bool(response, "success", false);
        obs_data_set_string(response, "error", "No server/key configured");
        return;
    }

    obs_encoder_t *venc = get_main_video_encoder();
    obs_encoder_t *aenc = get_main_audio_encoder();
    if (!venc || !aenc) {
        obs_data_set_bool(response, "success", false);
        obs_data_set_string(response, "error",
            "Main encoder not available. Is OBS streaming or is the encoder configured?");
        return;
    }

    OBSDataAutoRelease svc_settings = obs_data_create();
    obs_data_set_string(svc_settings, "server", mo.server.c_str());
    obs_data_set_string(svc_settings, "key", mo.key.c_str());

    std::string svc_name = std::string("chaoscast_svc_") + name;
    mo.service = obs_service_create("rtmp_custom", svc_name.c_str(), svc_settings, nullptr);
    if (!mo.service) {
        obs_data_set_bool(response, "success", false);
        obs_data_set_string(response, "error", "Failed to create RTMP service");
        return;
    }

    std::string out_name = std::string("chaoscast_") + name;
    OBSDataAutoRelease out_settings = obs_data_create();
    mo.output = obs_output_create("rtmp_output", out_name.c_str(), out_settings, nullptr);
    if (!mo.output) {
        obs_service_release(mo.service);
        mo.service = nullptr;
        obs_data_set_bool(response, "success", false);
        obs_data_set_string(response, "error", "Failed to create RTMP output");
        return;
    }

    obs_output_set_service(mo.output, mo.service);
    obs_output_set_video_encoder(mo.output, venc);
    obs_output_set_audio_encoder(mo.output, aenc, 0);

    auto sig = obs_output_get_signal_handler(mo.output);
    signal_handler_connect(sig, "start", on_output_started, &it->second.name);
    signal_handler_connect(sig, "stop", on_output_stopped, &it->second.name);

    if (!obs_output_start(mo.output)) {
        const char *err = obs_output_get_last_error(mo.output);
        mo.lastError = err ? err : "Unknown start error";
        blog(LOG_ERROR, TAG "start_output %s failed: %s", name, mo.lastError.c_str());

        signal_handler_disconnect(sig, "start", on_output_started, &it->second.name);
        signal_handler_disconnect(sig, "stop", on_output_stopped, &it->second.name);
        obs_output_release(mo.output);
        mo.output = nullptr;
        obs_service_release(mo.service);
        mo.service = nullptr;

        obs_data_set_bool(response, "success", false);
        obs_data_set_string(response, "error", mo.lastError.c_str());
        return;
    }

    blog(LOG_INFO, TAG "start_output: %s -> %s", name, mo.server.c_str());
    obs_data_set_bool(response, "success", true);
}

// ── stop_output handler ──
static void handle_stop_output(obs_data_t *request, obs_data_t *response, void *)
{
    const char *name = obs_data_get_string(request, "name");
    if (!name || !name[0]) {
        obs_data_set_bool(response, "success", false);
        obs_data_set_string(response, "error", "Missing 'name'");
        return;
    }

    std::lock_guard<std::mutex> lock(s_mutex);
    auto it = s_outputs.find(name);
    if (it == s_outputs.end()) {
        obs_data_set_bool(response, "success", false);
        obs_data_set_string(response, "error", "Output not found");
        return;
    }

    auto &mo = it->second;
    if (!mo.running && mo.output) {
        obs_data_set_bool(response, "success", true);
        obs_data_set_string(response, "info", "Already stopped");
        return;
    }

    if (mo.output) obs_output_stop(mo.output);

    blog(LOG_INFO, TAG "stop_output: %s", name);
    obs_data_set_bool(response, "success", true);
}

// ── remove_output handler ──
static void handle_remove_output(obs_data_t *request, obs_data_t *response, void *)
{
    const char *name = obs_data_get_string(request, "name");
    if (!name || !name[0]) {
        obs_data_set_bool(response, "success", false);
        obs_data_set_string(response, "error", "Missing 'name'");
        return;
    }

    std::lock_guard<std::mutex> lock(s_mutex);
    auto it = s_outputs.find(name);
    if (it == s_outputs.end()) {
        obs_data_set_bool(response, "success", true);
        obs_data_set_string(response, "info", "Output did not exist");
        return;
    }

    auto &mo = it->second;
    if (mo.output && mo.running) obs_output_force_stop(mo.output);
    if (mo.output) {
        auto sig = obs_output_get_signal_handler(mo.output);
        signal_handler_disconnect(sig, "start", on_output_started, &mo.name);
        signal_handler_disconnect(sig, "stop", on_output_stopped, &mo.name);
        obs_output_release(mo.output);
    }
    if (mo.service) obs_service_release(mo.service);
    s_outputs.erase(it);

    blog(LOG_INFO, TAG "remove_output: %s", name);
    obs_data_set_bool(response, "success", true);
}

// ── get_status handler ──
static void handle_get_status(obs_data_t *request, obs_data_t *response, void *)
{
    const char *filter_name = obs_data_get_string(request, "name");
    std::lock_guard<std::mutex> lock(s_mutex);

    OBSDataAutoRelease outputs_obj = obs_data_create();
    for (auto &[name, mo] : s_outputs) {
        if (filter_name && filter_name[0] && name != filter_name) continue;

        OBSDataAutoRelease entry = obs_data_create();
        obs_data_set_bool(entry, "running", mo.running);
        obs_data_set_string(entry, "server", mo.server.c_str());
        obs_data_set_string(entry, "error", mo.lastError.c_str());
        if (mo.running && mo.output) {
            obs_data_set_int(entry, "totalBytes", obs_output_get_total_bytes(mo.output));
            obs_data_set_int(entry, "totalFrames", obs_output_get_total_frames(mo.output));
            obs_data_set_int(entry, "droppedFrames", obs_output_get_frames_dropped(mo.output));
        }
        obs_data_set_obj(outputs_obj, name.c_str(), entry);
    }

    obs_data_set_obj(response, "outputs", outputs_obj);
    obs_data_set_bool(response, "success", true);
}

// ── Vendor Registration (called from obs_module_post_load) ──
void chaoscast_vendor_init()
{
    // Get obs-websocket's private proc_handler
    proc_handler_t *ph = get_websocket_ph();
    if (!ph) {
        blog(LOG_WARNING, TAG "Could not get obs-websocket proc handler. Is obs-websocket installed?");
        return;
    }

    // Register vendor "chaoscast"
    calldata_t cd = {0, 0, 0, 0};
    calldata_set_string(&cd, "name", "chaoscast");
    proc_handler_call(ph, "vendor_register", &cd);
    obs_websocket_vendor vendor = calldata_ptr(&cd, "vendor");
    calldata_free(&cd);

    if (!vendor) {
        blog(LOG_WARNING, TAG "vendor_register returned null");
        return;
    }

    blog(LOG_INFO, TAG "Registered vendor 'chaoscast' with obs-websocket");

    // Register request handlers using the official API pattern
    // The callback must be wrapped in obs_websocket_request_callback struct
    auto register_req = [&](const char *req_type,
                            obs_websocket_request_callback_function cb) {
        struct obs_websocket_request_callback req_cb = {cb, nullptr};

        calldata_t rcd = {0, 0, 0, 0};
        calldata_set_ptr(&rcd, "vendor", vendor);
        calldata_set_string(&rcd, "type", req_type);
        calldata_set_ptr(&rcd, "callback", &req_cb);

        proc_handler_call(ph, "vendor_request_register", &rcd);
        bool success = calldata_bool(&rcd, "success");
        calldata_free(&rcd);

        if (success) {
            blog(LOG_INFO, TAG "Registered request: %s", req_type);
        } else {
            blog(LOG_WARNING, TAG "Failed to register request: %s", req_type);
        }
    };

    register_req("add_output", handle_add_output);
    register_req("start_output", handle_start_output);
    register_req("stop_output", handle_stop_output);
    register_req("remove_output", handle_remove_output);
    register_req("get_status", handle_get_status);

    blog(LOG_INFO, TAG "All vendor requests registered successfully");
}

// ── Shutdown: clean up all managed outputs ──
void chaoscast_vendor_shutdown()
{
    std::lock_guard<std::mutex> lock(s_mutex);

    blog(LOG_INFO, TAG "Shutting down — cleaning up %zu managed outputs", s_outputs.size());

    for (auto it = s_outputs.begin(); it != s_outputs.end(); ) {
        auto &mo = it->second;

        // Force stop if running
        if (mo.output && mo.running) {
            blog(LOG_INFO, TAG "Force-stopping output: %s", mo.name.c_str());
            obs_output_force_stop(mo.output);
            mo.running = false;
        }

        // Disconnect signal handlers
        if (mo.output) {
            auto sig = obs_output_get_signal_handler(mo.output);
            if (sig) {
                signal_handler_disconnect(sig, "start", on_output_started, &mo.name);
                signal_handler_disconnect(sig, "stop", on_output_stopped, &mo.name);
            }
            obs_output_release(mo.output);
            mo.output = nullptr;
        }

        // Release service
        if (mo.service) {
            obs_service_release(mo.service);
            mo.service = nullptr;
        }

        blog(LOG_INFO, TAG "Cleaned up output: %s", mo.name.c_str());
        it = s_outputs.erase(it);
    }

    blog(LOG_INFO, TAG "All managed outputs cleaned up");
}