package com.example.local_llm_plugin

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.*
import java.util.concurrent.Executors
import android.os.Handler
import android.os.Looper

// External native methods for dynamic token limits
external fun setTokenLimit(limit: Int)
external fun generateResponseStreaming(prompt: String, maxTokens: Int)

/** LocalLlmPlugin */
class LocalLlmPlugin :
    FlutterPlugin,
    MethodCallHandler {
    // The MethodChannel that will the communication between Flutter and native Android
    //
    // This local reference serves to register the plugin with the Flutter Engine and unregister it
    // when the Flutter Engine is detached from the Activity
    private lateinit var channel: MethodChannel
    
    // Background executor for native calls
    private val executorService = Executors.newFixedThreadPool(4) { r ->
        Thread(r, "LLM-Background-Thread").apply { isDaemon = true }
    }
    private val mainHandler = Handler(Looper.getMainLooper())

    companion object {
        init {
            try {
                android.util.Log.d("LocalLlmPlugin", "Loading native library: local-llm-plugin")
                System.loadLibrary("local-llm-plugin")
                android.util.Log.d("LocalLlmPlugin", "Native library loaded successfully")
            } catch (e: UnsatisfiedLinkError) {
                android.util.Log.e("LocalLlmPlugin", "Failed to load native library: ${e.message}")
            }
        }
    }

    private external fun loadModel(filename: String): Boolean
    private external fun freeModel()
    private external fun generateResponse(prompt: String): String
    private external fun generateResponseStreaming(prompt: String, maxTokens: Int)
    private external fun getPlatformVersion(): String
    
    // Streaming callback methods - MUST be called from main thread
    fun onTokenReceived(token: String) {
        android.util.Log.d("LocalLlmPlugin", "Received streaming token: $token")
        // CRITICAL: Post to main thread for MethodChannel safety
        mainHandler.post {
            channel.invokeMethod("streaming_token", token)
        }
    }
    
    fun onStreamingComplete(fullResponse: String) {
        android.util.Log.d("LocalLlmPlugin", "Streaming complete: ${fullResponse.length} chars")
        // CRITICAL: Post to main thread for MethodChannel safety
        mainHandler.post {
            channel.invokeMethod("streaming_complete", fullResponse)
        }
    }

    private external fun setStreamingCallbacks()
    private external fun cleanupStreamingCallbacks()
    
    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "local_llm_plugin")
        channel.setMethodCallHandler(this)
        
        // Set up streaming callbacks when attached
        try {
            setStreamingCallbacks()
            android.util.Log.d("LocalLlmPlugin", "Streaming callbacks initialized")
        } catch (e: UnsatisfiedLinkError) {
            android.util.Log.e("LocalLlmPlugin", "Failed to set streaming callbacks: ${e.message}")
        }
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        when (call.method) {
            "getPlatformVersion" -> {
                try {
                    val version = getPlatformVersion()
                    android.util.Log.d("LocalLlmPlugin", "Platform version: $version")
                    // Fast call, can stay on main thread
                    result.success(version)
                } catch (e: UnsatisfiedLinkError) {
                    android.util.Log.e("LocalLlmPlugin", "UnsatisfiedLinkError in getPlatformVersion: ${e.message}")
                    result.error("LINK_ERROR", "Native library not loaded: ${e.message}", null)
                } catch (e: Exception) {
                    android.util.Log.e("LocalLlmPlugin", "Exception in getPlatformVersion: ${e.message}")
                    result.error("VERSION_EXCEPTION", "Exception getting version: ${e.message}", null)
                }
            }
            "loadModel" -> {
                val modelPath = call.argument<String>("modelPath")
                if (modelPath != null) {
                    android.util.Log.d("LocalLlmPlugin", "Loading model from: $modelPath on background thread")
                    // Move to background thread to prevent blocking main thread
                    executorService.execute {
                        try {
                            val success = loadModel(modelPath)
                            // Post result back to main thread
                            mainHandler.post {
                                android.util.Log.d("LocalLlmPlugin", "Load model result: $success")
                                if (success) {
                                    result.success("Model loaded successfully from $modelPath")
                                } else {
                                    result.error("LOAD_FAILED", "Failed to load model from $modelPath", null)
                                }
                            }
                        } catch (e: UnsatisfiedLinkError) {
                            mainHandler.post {
                                android.util.Log.e("LocalLlmPlugin", "UnsatisfiedLinkError: ${e.message}")
                                result.error("LINK_ERROR", "Native library not loaded: ${e.message}", null)
                            }
                        } catch (e: Exception) {
                            mainHandler.post {
                                android.util.Log.e("LocalLlmPlugin", "Exception loading model: ${e.message}")
                                result.error("LOAD_EXCEPTION", "Exception loading model: ${e.message}", null)
                            }
                        }
                    }
                    // Don't wait for result, return immediately to keep UI responsive
                    return
                } else {
                    result.error("INVALID_ARGUMENT", "modelPath is null", null)
                }
            }
            "generateResponse" -> {
                val prompt = call.argument<String>("prompt")
                if (prompt != null) {
                    android.util.Log.d("LocalLlmPlugin", "About to call native generateResponse for prompt: \"$prompt\" on background thread")
                    // Move to background thread to prevent blocking main thread
                    executorService.execute {
                        try {
                            val response = generateResponse(prompt)
                            // Post result back to main thread
                            mainHandler.post {
                                android.util.Log.d("LocalLlmPlugin", "Native call succeeded, response: \"$response\"")
                                result.success(response)
                            }
                        } catch (e: UnsatisfiedLinkError) {
                            mainHandler.post {
                                android.util.Log.e("LocalLlmPlugin", "UnsatisfiedLinkError in generateResponse: ${e.message}")
                                result.error("LINK_ERROR", "Native library not loaded in generateResponse: ${e.message}", null)
                            }
                        } catch (e: Exception) {
                            mainHandler.post {
                                android.util.Log.e("LocalLlmPlugin", "Unexpected exception in generateResponse: ${e.message}")
                                result.error("GENERATION_EXCEPTION", "Exception generating response: ${e.message}", null)
                            }
                        }
                    }
                    // Don't wait for result, return immediately to keep UI responsive
                    return
                } else {
                    result.error("INVALID_ARGUMENT", "prompt is null", null)
                }
            }
            "freeModel" -> {
                try {
                    freeModel()
                    result.success("Model freed successfully")
                } catch (e: Exception) {
                    result.error("FREE_EXCEPTION", "Exception freeing model: ${e.message}", null)
                }
            }
            "generateResponseStreaming" -> {
                val prompt = call.argument<String>("prompt")
                val maxTokens = call.argument<Int>("maxTokens") ?: 200 // Default to 200 tokens
                
                if (prompt != null) {
                    android.util.Log.d("LocalLlmPlugin", "Starting streaming generation for prompt: \"$prompt\" with maxTokens: $maxTokens on background thread")
                    
                    // Return immediately to keep UI responsive
                    result.success("Streaming started")
                    
                    // Move to background thread to prevent blocking main thread
                    executorService.execute {
                        try {
                            // Set the token limit before calling native function
                            setTokenLimit(maxTokens)
                            
                            // Call native streaming method with token limit
                            generateResponseStreaming(prompt, maxTokens)
                        } catch (e: UnsatisfiedLinkError) {
                            mainHandler.post {
                                android.util.Log.e("LocalLlmPlugin", "UnsatisfiedLinkError in generateResponseStreaming: ${e.message}")
                                // Send error through EventChannel if streaming was already started
                                channel.invokeMethod("streaming_error", "Native library not loaded: ${e.message}")
                            }
                        } catch (e: Exception) {
                            mainHandler.post {
                                android.util.Log.e("LocalLlmPlugin", "Exception in generateResponseStreaming: ${e.message}")
                                // Send error through EventChannel if streaming was already started
                                channel.invokeMethod("streaming_error", "Exception in streaming generation: ${e.message}")
                            }
                        }
                    }
                } else {
                    result.error("INVALID_ARGUMENT", "prompt is null", null)
                }
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        
        // Cleanup streaming callbacks
        try {
            cleanupStreamingCallbacks()
        } catch (e: UnsatisfiedLinkError) {
            android.util.Log.e("LocalLlmPlugin", "Failed to cleanup streaming callbacks: ${e.message}")
        }
        
        // Cleanup background executor
        executorService.shutdown()
    }
}
