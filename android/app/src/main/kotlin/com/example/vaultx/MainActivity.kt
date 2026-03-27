package com.example.vaultx // Keep your actual package name here!

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity: FlutterFragmentActivity() { 
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // NO MORE BYPASS. This locks down the screen 100% of the time.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}