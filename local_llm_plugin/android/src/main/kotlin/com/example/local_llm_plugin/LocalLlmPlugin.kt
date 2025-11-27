package com.example.local_llm_plugin

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** LocalLlmPlugin */
class LocalLlmPlugin :
    FlutterPlugin,
    MethodCallHandler {
    // The MethodChannel that will the communication between Flutter and native Android
    //
    // This local reference serves to register the plugin with the Flutter Engine and unregister it
    // when the Flutter Engine is detached from the Activity
    private lateinit var channel: MethodChannel

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
    private external fun generateResponseStreaming(prompt: String)
    private external fun getPlatformVersion(): String

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "local_llm_plugin")
        channel.setMethodCallHandler(this)
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
                    android.util.Log.d("LocalLlmPlugin", "Loading model from: $modelPath")
                    try {
                        val success = loadModel(modelPath)
                        android.util.Log.d("LocalLlmPlugin", "Load model result: $success")
                        if (success) {
                            result.success("Model loaded successfully from $modelPath")
                        } else {
                            result.error("LOAD_FAILED", "Failed to load model from $modelPath", null)
                        }
                    } catch (e: UnsatisfiedLinkError) {
                        android.util.Log.e("LocalLlmPlugin", "UnsatisfiedLinkError: ${e.message}")
                        result.error("LINK_ERROR", "Native library not loaded: ${e.message}", null)
                    } catch (e: Exception) {
                        android.util.Log.e("LocalLlmPlugin", "Exception loading model: ${e.message}")
                        result.error("LOAD_EXCEPTION", "Exception loading model: ${e.message}", null)
                    }
                } else {
                    result.error("INVALID_ARGUMENT", "modelPath is null", null)
                }
            }
            "generateResponse" -> {
                val prompt = call.argument<String>("prompt")
                if (prompt != null) {
                    android.util.Log.d("LocalLlmPlugin", "About to call native generateResponse for prompt: \"$prompt\"")
                    try {
                        val response = generateResponse(prompt)
                        android.util.Log.d("LocalLlmPlugin", "Native call succeeded, response: \"$response\"")
                        result.success(response)
                    } catch (e: UnsatisfiedLinkError) {
                        android.util.Log.e("LocalLlmPlugin", "UnsatisfiedLinkError in generateResponse: ${e.message}")
                        result.error("LINK_ERROR", "Native library not loaded in generateResponse: ${e.message}", null)
                    } catch (e: Exception) {
                        android.util.Log.e("LocalLlmPlugin", "Unexpected exception in generateResponse: ${e.message}")
                        result.error("GENERATION_EXCEPTION", "Exception generating response: ${e.message}", null)
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
                if (prompt != null) {
                    android.util.Log.d("LocalLlmPlugin", "Starting streaming generation for prompt: \"$prompt\"")
                    try {
                        // Call native streaming method
                        generateResponseStreaming(prompt)
                        result.success("Streaming started successfully")
                    } catch (e: UnsatisfiedLinkError) {
                        android.util.Log.e("LocalLlmPlugin", "UnsatisfiedLinkError in generateResponseStreaming: ${e.message}")
                        result.error("LINK_ERROR", "Native library not loaded: ${e.message}", null)
                    } catch (e: Exception) {
                        android.util.Log.e("LocalLlmPlugin", "Exception in generateResponseStreaming: ${e.message}")
                        result.error("STREAMING_EXCEPTION", "Exception in streaming generation: ${e.message}", null)
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
    }
}
