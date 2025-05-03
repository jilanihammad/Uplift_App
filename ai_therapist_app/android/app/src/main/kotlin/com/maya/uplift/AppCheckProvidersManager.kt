package com.maya.uplift

import android.content.Context
import android.util.Log
import com.google.android.gms.tasks.Tasks
import com.google.firebase.FirebaseApp
import com.google.firebase.appcheck.FirebaseAppCheck
import com.google.firebase.appcheck.debug.DebugAppCheckProviderFactory
import com.google.firebase.appcheck.playintegrity.PlayIntegrityAppCheckProviderFactory
import java.util.concurrent.TimeUnit

/**
 * Dedicated manager for Firebase App Check providers
 * Handles initialization, provider installation, and fallbacks
 */
class AppCheckProvidersManager(private val context: Context) {
    companion object {
        private const val TAG = "AppCheckManager"
        private const val DEFAULT_TIMEOUT_SECONDS = 5L
    }

    /**
     * Initialize App Check with appropriate provider
     * Uses Play Integrity in release builds, Debug provider in debug builds
     * Falls back to Debug provider if Play Integrity fails
     */
    fun initialize() {
        try {
            Log.d(TAG, "Initializing App Check providers...")
            
            // Get or initialize Firebase
            val firebaseApp = try {
                FirebaseApp.getInstance()
            } catch (e: Exception) {
                FirebaseApp.initializeApp(context)
            }
            
            // Get App Check instance
            val firebaseAppCheck = FirebaseAppCheck.getInstance()
            
            // Determine if this is a debug build
            val isDebug = isDebugBuild()
            Log.d(TAG, "Build type: ${if (isDebug) "DEBUG" else "RELEASE"}")
            
            if (isDebug) {
                installDebugProvider(firebaseAppCheck)
            } else {
                // Try Play Integrity first, fall back to Debug if needed
                try {
                    installPlayIntegrityProvider(firebaseAppCheck)
                } catch (e: Exception) {
                    Log.e(TAG, "Error installing Play Integrity provider: ${e.message}")
                    installDebugProvider(firebaseAppCheck)
                }
            }
            
            // Verify provider was installed by getting a token
            verifyProviderWorks(firebaseAppCheck)
            
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing App Check: ${e.message}")
            e.printStackTrace()
            // Last resort - try to install debug provider directly
            try {
                val appCheck = FirebaseAppCheck.getInstance()
                appCheck.installAppCheckProviderFactory(DebugAppCheckProviderFactory.getInstance())
                Log.d(TAG, "Installed fallback Debug provider after error")
            } catch (fallbackError: Exception) {
                Log.e(TAG, "Even fallback provider installation failed: ${fallbackError.message}")
            }
        }
    }
    
    /**
     * Install Debug provider for testing
     */
    private fun installDebugProvider(appCheck: FirebaseAppCheck) {
        try {
            Log.d(TAG, "Installing Debug provider...")
            appCheck.installAppCheckProviderFactory(DebugAppCheckProviderFactory.getInstance())
            Log.d(TAG, "Debug provider installed successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to install Debug provider: ${e.message}")
            throw e
        }
    }
    
    /**
     * Install Play Integrity provider for production
     */
    private fun installPlayIntegrityProvider(appCheck: FirebaseAppCheck) {
        try {
            Log.d(TAG, "Installing Play Integrity provider...")
            appCheck.installAppCheckProviderFactory(PlayIntegrityAppCheckProviderFactory.getInstance())
            Log.d(TAG, "Play Integrity provider installed successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to install Play Integrity provider: ${e.message}")
            throw e
        }
    }
    
    /**
     * Verify the provider works by getting a token
     */
    private fun verifyProviderWorks(appCheck: FirebaseAppCheck) {
        try {
            Log.d(TAG, "Verifying App Check provider...")
            
            // Use Tasks API to avoid blocking the main thread
            val task = appCheck.getToken(false)
            
            // Wait with timeout to avoid ANR
            val result = Tasks.await(task, DEFAULT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            
            if (result != null && result.token.isNotEmpty()) {
                Log.d(TAG, "App Check verification successful! Token starts with: ${result.token.take(5)}...")
            } else {
                Log.w(TAG, "App Check token is null or empty")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error verifying App Check provider: ${e.message}")
            e.printStackTrace()
        }
    }
    
    /**
     * Determine if this is a debug build
     */
    private fun isDebugBuild(): Boolean {
        return android.os.Build.FINGERPRINT.contains("debug") ||
                context.packageManager.getApplicationInfo(context.packageName, 0).flags and 
                android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0
    }
} 