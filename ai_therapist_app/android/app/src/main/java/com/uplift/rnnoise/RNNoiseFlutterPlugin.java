package com.uplift.rnnoise;

import android.util.Log;
import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.ShortBuffer;
import java.util.ArrayList;

public class RNNoiseFlutterPlugin implements FlutterPlugin, MethodCallHandler {
    private static final String TAG = "RNNoiseFlutterPlugin";
    private static final String CHANNEL = "rnnoise_flutter";
    
    private MethodChannel channel;
    private RNNoiseFlutter rnnoise;
    
    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
        channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), CHANNEL);
        channel.setMethodCallHandler(this);
        rnnoise = new RNNoiseFlutter();
        Log.d(TAG, "RNNoiseFlutterPlugin attached to engine");
    }
    
    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        try {
            switch (call.method) {
                case "initialize":
                    handleInitialize(result);
                    break;
                case "processAudio":
                    handleProcessAudio(call, result);
                    break;
                case "getVadProbability":
                    handleGetVadProbability(result);
                    break;
                case "reset":
                    handleReset(result);
                    break;
                case "dispose":
                    handleDispose(result);
                    break;
                case "isInitialized":
                    handleIsInitialized(result);
                    break;
                default:
                    result.notImplemented();
                    break;
            }
        } catch (Exception e) {
            Log.e(TAG, "Error handling method call: " + call.method, e);
            result.error("ERROR", "Failed to execute " + call.method + ": " + e.getMessage(), null);
        }
    }
    
    private void handleInitialize(Result result) {
        boolean success = rnnoise.initialize();
        Log.d(TAG, "RNNoise initialization: " + success);
        result.success(success);
    }
    
    private void handleProcessAudio(MethodCall call, Result result) {
        ArrayList<Integer> audioData = call.argument("audioData");
        if (audioData == null || audioData.size() != 480) {
            result.error("INVALID_ARGUMENT", "Audio data must contain exactly 480 samples", null);
            return;
        }
        
        // Convert ArrayList<Integer> to short[]
        short[] audioArray = new short[480];
        for (int i = 0; i < 480; i++) {
            audioArray[i] = audioData.get(i).shortValue();
        }
        
        byte[] processedData = rnnoise.processAudio(audioArray);
        if (processedData != null) {
            result.success(processedData);
        } else {
            result.error("PROCESSING_FAILED", "Failed to process audio data", null);
        }
    }
    
    private void handleGetVadProbability(Result result) {
        float probability = rnnoise.getVadProbability();
        result.success((double) probability);
    }
    
    private void handleReset(Result result) {
        rnnoise.reset();
        result.success(null);
    }
    
    private void handleDispose(Result result) {
        rnnoise.dispose();
        result.success(null);
    }
    
    private void handleIsInitialized(Result result) {
        boolean initialized = rnnoise.isInitialized();
        result.success(initialized);
    }
    
    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        if (rnnoise != null) {
            rnnoise.dispose();
        }
        Log.d(TAG, "RNNoiseFlutterPlugin detached from engine");
    }
}