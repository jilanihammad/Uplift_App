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
        
        Log.d(TAG, "Application onCreate called - NO APP CHECK VERSION")
        
        try {
            // ONLY initialize Firebase - NO APP CHECK
            try {
                val app = FirebaseApp.getInstance()
                Log.d(TAG, "Using existing Firebase app - NO APP CHECK")
            } catch (e: Exception) {
                FirebaseApp.initializeApp(this)
                Log.d(TAG, "Initialized Firebase - NO APP CHECK")
            }
            
            // NO APP CHECK INITIALIZATION - it's causing problems
            Log.d(TAG, "App Check has been DISABLED to fix issues")
            
        } catch (e: Exception) {
            Log.e(TAG, "Error during initialization: ${e.message}")
            e.printStackTrace()
        }
    }
} 