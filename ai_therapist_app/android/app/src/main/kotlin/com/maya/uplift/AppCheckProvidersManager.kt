package com.maya.uplift

import android.content.Context
import android.util.Log
import com.google.android.gms.tasks.Tasks
import com.google.firebase.FirebaseApp
import com.google.firebase.appcheck.AppCheckProviderFactory
import com.google.firebase.appcheck.FirebaseAppCheck
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
        val isDebug = isDebugBuild()

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

            Log.d(TAG, "Build type: ${if (isDebug) "DEBUG" else "RELEASE"}")

            if (isDebug) {
                installDebugProvider(firebaseAppCheck)
            } else {
                // Try Play Integrity first, fall back to Debug if needed
                try {
                    installPlayIntegrityProvider(firebaseAppCheck)
                } catch (e: Exception) {
                    Log.e(TAG, "Error installing Play Integrity provider: ${e.message}")
                    throw IllegalStateException("Play Integrity provider installation failed", e)
                }
            }
            
            // Verify provider was installed by getting a token
            verifyProviderWorks(firebaseAppCheck)
            
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing App Check: ${e.message}")
            e.printStackTrace()

            if (isDebug) {
                try {
                    val appCheck = FirebaseAppCheck.getInstance()
                    val factory = getDebugProviderFactory()
                    if (factory != null) {
                        appCheck.installAppCheckProviderFactory(factory)
                        Log.d(TAG, "Installed fallback Debug provider after error in debug mode")
                    } else {
                        Log.w(TAG, "Debug provider factory not available during fallback")
                    }
                } catch (fallbackError: Exception) {
                    Log.e(TAG, "Even fallback provider installation failed: ${fallbackError.message}")
                }
            } else {
                throw e
            }
        }
    }
    
    /**
     * Install Debug provider for testing
     */
    private fun installDebugProvider(appCheck: FirebaseAppCheck) {
        try {
            Log.d(TAG, "Installing Debug provider...")
            val factory = getDebugProviderFactory()
            if (factory != null) {
                appCheck.installAppCheckProviderFactory(factory)
                Log.d(TAG, "Debug provider installed successfully")
            } else {
                Log.w(TAG, "Debug provider factory not found; skipping install")
                throw IllegalStateException("Debug App Check provider not present")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to install Debug provider: ${e.message}")
            throw e
        }
    }

    private fun getDebugProviderFactory(): AppCheckProviderFactory? {
        return try {
            val factoryClass = Class.forName("com.google.firebase.appcheck.debug.DebugAppCheckProviderFactory")
            val getInstance = factoryClass.getMethod("getInstance")
            val factory = getInstance.invoke(null)
            if (factory is AppCheckProviderFactory) {
                factory
            } else {
                Log.w(TAG, "Unexpected debug provider factory type: ${factory?.javaClass?.name}")
                null
            }
        } catch (classNotFound: ClassNotFoundException) {
            Log.w(TAG, "DebugAppCheckProviderFactory class not found on classpath")
            null
        } catch (reflectionError: Exception) {
            Log.e(TAG, "Failed to obtain DebugAppCheckProviderFactory: ${reflectionError.message}")
            null
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
