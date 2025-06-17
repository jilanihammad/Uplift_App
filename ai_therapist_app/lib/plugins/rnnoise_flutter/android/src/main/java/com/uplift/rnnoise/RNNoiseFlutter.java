package com.uplift.rnnoise;

import android.util.Log;

public class RNNoiseFlutter {
    private static final String TAG = "RNNoiseFlutter";
    
    static {
        try {
            System.loadLibrary("rnnoise_flutter");
            Log.d(TAG, "RNNoise native library loaded successfully");
        } catch (UnsatisfiedLinkError e) {
            Log.e(TAG, "Failed to load RNNoise native library", e);
        }
    }
    
    /**
     * Initialize RNNoise library
     * @return true if initialization was successful
     */
    public native boolean initialize();
    
    /**
     * Process audio frame through RNNoise
     * @param audioData 16-bit PCM audio frame (480 samples)
     * @return processed audio data as byte array
     */
    public native byte[] processAudio(short[] audioData);
    
    /**
     * Get VAD probability from last processed frame
     * @return VAD probability (0.0 to 1.0)
     */
    public native float getVadProbability();
    
    /**
     * Reset RNNoise internal state
     */
    public native void reset();
    
    /**
     * Dispose of RNNoise resources
     */
    public native void dispose();
    
    /**
     * Check if RNNoise is initialized
     * @return true if initialized
     */
    public native boolean isInitialized();
}