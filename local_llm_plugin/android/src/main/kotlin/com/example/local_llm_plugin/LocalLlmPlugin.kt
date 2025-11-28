package com.example.local_llm_plugin

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.*
import java.util.concurrent.Executors
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
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
    
    // OPTIMIZED: Single-thread executor to prevent thread overload on mobile devices
    private val executorService = Executors.newSingleThreadExecutor { r ->
        Thread(r, "LLM-Optimized-Thread").apply { 
            isDaemon = true
            priority = Thread.NORM_PRIORITY - 1 // Lower priority to preserve UI responsiveness
        }
    }
    
    // Operation throttling to prevent concurrent overload
    private val isProcessing = AtomicBoolean(false)
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
    
    /**
     * Execute operation with throttling to prevent concurrent overload
     */
    private fun executeWithThrottling(operation: () -> Unit): Boolean {
        return if (isProcessing.compareAndSet(false, true)) {
            executorService.execute {
                try {
                    operation()
                } catch (e: Exception) {
                    android.util.Log.e("LocalLlmPlugin", "Error in throttled operation: ${e.message}")
                } finally {
                    isProcessing.set(false)
                }
            }
            true
        } else {
            android.util.Log.w("LocalLlmPlugin", "Operation skipped - already processing")
            false
        }
    }
    
    /**
     * Enhanced cleanup with proper resource management
     */
    private fun cleanupExecutor() {
        try {
            android.util.Log.d("LocalLlmPlugin", "Cleaning up executor service...")
            executorService.shutdown()
            if (!executorService.awaitTermination(5, TimeUnit.SECONDS)) {
                android.util.Log.w("LocalLlmPlugin", "Executor shutdown timeout, forcing shutdown")
                executorService.shutdownNow()
            }
            android.util.Log.d("LocalLlmPlugin", "Executor cleanup completed")
        } catch (e: InterruptedException) {
            android.util.Log.e("LocalLlmPlugin", "Interrupted during executor cleanup", e)
            executorService.shutdownNow()
            Thread.currentThread().interrupt()
        }
    }

    private external fun loadModel(filename: String): Boolean
    private external fun freeModel()
    private external fun generateResponse(prompt: String): String
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
                    android.util.Log.d("LocalLlmPlugin", "Loading model from: $modelPath with optimized threading")
                    
                    // Return immediately to keep UI responsive
                    result.success("Model loading started for $modelPath")
                    
                    // Use throttled execution to prevent concurrent operations
                    executeWithThrottling {
                        try {
                            android.util.Log.d("LocalLlmPlugin", "Starting model load on optimized thread")
                            val success = loadModel(modelPath)
                            // Post result back to main thread
                            mainHandler.post {
                                android.util.Log.d("LocalLlmPlugin", "Load model result: $success")
                                if (success) {
                                    channel.invokeMethod("model_loaded", "Model loaded successfully from $modelPath")
                                } else {
                                    channel.invokeMethod("model_load_error", "Failed to load model from $modelPath")
                                }
                            }
                        } catch (e: UnsatisfiedLinkError) {
                            mainHandler.post {
                                android.util.Log.e("LocalLlmPlugin", "UnsatisfiedLinkError: ${e.message}")
                                channel.invokeMethod("model_load_error", "Native library not loaded: ${e.message}")
                            }
                        } catch (e: Exception) {
                            mainHandler.post {
                                android.util.Log.e("LocalLlmPlugin", "Exception loading model: ${e.message}")
                                channel.invokeMethod("model_load_error", "Exception loading model: ${e.message}")
                            }
                        }
                    }
                } else {
                    result.error("INVALID_ARGUMENT", "modelPath is null", null)
                }
            }
            "generateResponse" -> {
                val prompt = call.argument<String>("prompt")
                if (prompt != null) {
                    android.util.Log.d("LocalLlmPlugin", "About to call native generateResponse with optimized threading")
                    
                    // Return immediately to keep UI responsive
                    result.success("Response generation started")
                    
                    // Use throttled execution to prevent concurrent operations
                    executeWithThrottling {
                        try {
                            android.util.Log.d("LocalLlmPlugin", "Starting response generation on optimized thread")
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
                val maxTokens = call.argument<Int>("maxTokens") ?: 200 // Default to 200 tokens (will be overridden by C++)
                
                if (prompt != null) {
                    android.util.Log.d("LocalLlmPlugin", "Starting Phase 3 C++ classification streaming - TEMPORARILY DISABLING THROTTLING")
                    
                    // Return immediately to keep UI responsive
                    result.success("C++ streaming started")
                    
                    // TEMPORARY FIX: Execute directly without throttling to test C++ call
                    executorService.execute {
                        try {
                            android.util.Log.d("LocalLlmPlugin", "About to call C++ generateResponseStreaming with: \"$prompt\"")
                            
                            // Call native streaming method - C++ will classify question and set optimal token limit
                            generateResponseStreaming(prompt, maxTokens)
                            
                            android.util.Log.d("LocalLlmPlugin", "C++ generateResponseStreaming call completed")
                        } catch (e: UnsatisfiedLinkError) {
                            mainHandler.post {
                                android.util.Log.e("LocalLlmPlugin", "UnsatisfiedLinkError in generateResponseStreaming: ${e.message}")
                                channel.invokeMethod("streaming_error", "Native library not loaded: ${e.message}")
                            }
                        } catch (e: Exception) {
                            mainHandler.post {
                                android.util.Log.e("LocalLlmPlugin", "Exception in generateResponseStreaming: ${e.message}")
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
            android.util.Log.d("LocalLlmPlugin", "Streaming callbacks cleaned up")
        } catch (e: UnsatisfiedLinkError) {
            android.util.Log.e("LocalLlmPlugin", "Failed to cleanup streaming callbacks: ${e.message}")
        }
        
        // Enhanced cleanup with proper resource management
        cleanupExecutor()
    }
}
