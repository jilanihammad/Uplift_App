package com.maya.uplift

import android.app.Application
import android.util.Log
import com.google.firebase.FirebaseApp

class UpliftApplication : Application() {
    companion object {
        private const val TAG = "UpliftApplication"
    }

    override fun onCreate() {
        super.onCreate()

        Log.d(TAG, "Application onCreate called")

        try {
            val firebaseApp = try {
                FirebaseApp.getInstance()
            } catch (e: Exception) {
                FirebaseApp.initializeApp(this)?.also {
                    Log.d(TAG, "Initialized Firebase app instance")
                }
            }

            if (firebaseApp == null) {
                Log.e(TAG, "Failed to initialize Firebase app; App Check cannot proceed")
                return
            }

            AppCheckProvidersManager(this).initialize()
            Log.d(TAG, "Firebase App Check initialization complete")
        } catch (e: Exception) {
            Log.e(TAG, "Error during App Check initialization", e)
        }
    }
} 
