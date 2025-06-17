#include <jni.h>
#include <android/log.h>
#include <vector>
#include <memory>
#include <cstring>
#include <algorithm>
#include "rnnoise.h"

#define LOG_TAG "RNNoiseFlutter"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// Global RNNoise state
static DenoiseState* g_rnnoise_state = nullptr;
static bool g_initialized = false;
static float g_last_vad_prob = 0.0f;

extern "C" {

JNIEXPORT jboolean JNICALL
Java_com_uplift_rnnoise_RNNoiseFlutter_initialize(JNIEnv *env, jobject thiz) {
    LOGD("Initializing RNNoise...");
    
    if (g_initialized) {
        LOGD("RNNoise already initialized");
        return JNI_TRUE;
    }
    
    try {
        g_rnnoise_state = rnnoise_create(nullptr);
        if (g_rnnoise_state == nullptr) {
            LOGE("Failed to create RNNoise state");
            return JNI_FALSE;
        }
        
        g_initialized = true;
        g_last_vad_prob = 0.0f;
        LOGD("RNNoise initialized successfully");
        return JNI_TRUE;
    } catch (const std::exception& e) {
        LOGE("Exception during RNNoise initialization: %s", e.what());
        return JNI_FALSE;
    }
}

JNIEXPORT jbyteArray JNICALL
Java_com_uplift_rnnoise_RNNoiseFlutter_processAudio(JNIEnv *env, jobject thiz, jshortArray audio_data) {
    if (!g_initialized || g_rnnoise_state == nullptr) {
        LOGE("RNNoise not initialized");
        return nullptr;
    }
    
    jsize length = env->GetArrayLength(audio_data);
    if (length != 480) {
        LOGE("Invalid audio frame size: %d (expected 480)", length);
        return nullptr;
    }
    
    // Get audio data from Java
    jshort* input_data = env->GetShortArrayElements(audio_data, nullptr);
    if (input_data == nullptr) {
        LOGE("Failed to get audio data");
        return nullptr;
    }
    
    // Convert to float for RNNoise processing
    std::vector<float> input_float(480);
    for (int i = 0; i < 480; i++) {
        input_float[i] = static_cast<float>(input_data[i]);
    }
    
    // Process with RNNoise
    g_last_vad_prob = rnnoise_process_frame(g_rnnoise_state, input_float.data(), input_float.data());
    
    // Convert back to int16
    std::vector<int16_t> output_int16(480);
    for (int i = 0; i < 480; i++) {
        float sample = input_float[i];
        // Clamp to int16 range
        sample = std::max(-32768.0f, std::min(32767.0f, sample));
        output_int16[i] = static_cast<int16_t>(sample);
    }
    
    // Release Java array
    env->ReleaseShortArrayElements(audio_data, input_data, JNI_ABORT);
    
    // Create result byte array (convert int16 to bytes)
    jbyteArray result = env->NewByteArray(480 * 2);
    if (result != nullptr) {
        env->SetByteArrayRegion(result, 0, 480 * 2, reinterpret_cast<const jbyte*>(output_int16.data()));
    }
    
    return result;
}

JNIEXPORT jfloat JNICALL
Java_com_uplift_rnnoise_RNNoiseFlutter_getVadProbability(JNIEnv *env, jobject thiz) {
    return g_last_vad_prob;
}

JNIEXPORT void JNICALL
Java_com_uplift_rnnoise_RNNoiseFlutter_reset(JNIEnv *env, jobject thiz) {
    if (g_initialized && g_rnnoise_state != nullptr) {
        LOGD("Resetting RNNoise state");
        rnnoise_destroy(g_rnnoise_state);
        g_rnnoise_state = rnnoise_create(nullptr);
        g_last_vad_prob = 0.0f;
    }
}

JNIEXPORT void JNICALL
Java_com_uplift_rnnoise_RNNoiseFlutter_dispose(JNIEnv *env, jobject thiz) {
    LOGD("Disposing RNNoise");
    if (g_rnnoise_state != nullptr) {
        rnnoise_destroy(g_rnnoise_state);
        g_rnnoise_state = nullptr;
    }
    g_initialized = false;
    g_last_vad_prob = 0.0f;
}

JNIEXPORT jboolean JNICALL
Java_com_uplift_rnnoise_RNNoiseFlutter_isInitialized(JNIEnv *env, jobject thiz) {
    return g_initialized ? JNI_TRUE : JNI_FALSE;
}

} // extern "C"