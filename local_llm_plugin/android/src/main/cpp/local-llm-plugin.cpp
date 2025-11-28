#include <android/log.h>
#include <jni.h>
#include <iomanip>
#include <math.h>
#include <string>
#include <unistd.h>
#include <algorithm>
#include <thread>
#include <atomic>
#include <chrono>
#include "llama.h"
#include "common.h"

// Include question classification system for Phase 3
#include "question_classifier.cpp"

// Write C++ code here.
//
// Do not forget to dynamically load the C++ library into your application.
//
// For instance,
//
// In MainActivity.java:
//    static {
//       System.loadLibrary("local-llm-plugin");
//    }
//
// Or, in MainActivity.kt:
//    companion object {
//      init {
//         System.loadLibrary("local-llm-plugin")
//      }
//    }

#define TAG "local-llm-plugin.cpp"
#define LOGi(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGe(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

static llama_model *model = nullptr;
static llama_context *context = nullptr;
static llama_sampler *sampler = nullptr;
static llama_batch batch = {0, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr};
static std::string cached_token_chars;

// Global variables for streaming callbacks
static JavaVM* g_vm = nullptr;
static jobject g_callback_object = nullptr;
static jmethodID g_send_token_method = nullptr;
static jmethodID g_streaming_complete_method = nullptr;
static std::atomic<bool> g_is_streaming{false};
static std::atomic<int> g_current_token_limit{200}; // Default 200 tokens

// CRITICAL DEBUG: Add comprehensive logging for model state tracking
static void logModelState(const char* context_msg) {
    LOGi("=== MODEL STATE DEBUG [%s] ===", context_msg);
    LOGi("model pointer: %p", (void*)model);
    LOGi("context pointer: %p", (void*)context); 
    LOGi("sampler pointer: %p", (void*)sampler);
    LOGi("batch.token: %p", (void*)batch.token);
    LOGi("model loaded: %s", model ? "YES" : "NO");
    LOGi("context loaded: %s", context ? "YES" : "NO");
    LOGi("sampler loaded: %s", sampler ? "YES" : "NO");
    LOGi("=== END MODEL STATE DEBUG ===");
}

// Static initialization debug
__attribute__((constructor))
static void init_debug() {
    logModelState("STATIC_INIT");
}

bool is_valid_utf8(const char * string) {
    if (!string) {
        return true;
    }

    const unsigned char * bytes = (const unsigned char *)string;
    int num;

    while (*bytes != 0x00) {
        if ((*bytes & 0x80) == 0x00) {
            // U+0000 to U+007F
            num = 1;
        } else if ((*bytes & 0xE0) == 0xC0) {
            // U+0080 to U+07FF
            num = 2;
        } else if ((*bytes & 0xF0) == 0xE0) {
            // U+0800 to U+FFFF
            num = 3;
        } else if ((*bytes & 0xF8) == 0xF0) {
            // U+10000 to U+10FFFF
            num = 4;
        } else {
            return false;
        }

        bytes += 1;
        for (int i = 1; i < num; ++i) {
            if ((*bytes & 0xC0) != 0x80) {
                return false;
            }
            bytes += 1;
        }
    }

    return true;
}

static void log_callback(ggml_log_level level, const char * fmt, void * data) {
    if (level == GGML_LOG_LEVEL_ERROR)     __android_log_print(ANDROID_LOG_ERROR, TAG, fmt, data);
    else if (level == GGML_LOG_LEVEL_INFO) __android_log_print(ANDROID_LOG_INFO, TAG, fmt, data);
    else if (level == GGML_LOG_LEVEL_WARN) __android_log_print(ANDROID_LOG_WARN, TAG, fmt, data);
    else __android_log_print(ANDROID_LOG_DEFAULT, TAG, fmt, data);
}

// JNI utility functions for callback management
static void sendTokenToJava(const std::string& token) {
    if (!g_vm || !g_callback_object || !g_send_token_method || !g_is_streaming.load()) {
        return;
    }
    
    JNIEnv* env;
    if (g_vm->AttachCurrentThread(&env, nullptr) != JNI_OK) {
        LOGe("Failed to attach to Java thread for token callback");
        return;
    }
    
    jstring jToken = env->NewStringUTF(token.c_str());
    env->CallVoidMethod(g_callback_object, g_send_token_method, jToken);
    env->DeleteLocalRef(jToken);
    
    // Detach if needed
    if (env->ExceptionCheck()) {
        env->ExceptionClear();
    }
}

static void completeStreamingToJava(const std::string& fullResponse) {
    if (!g_vm || !g_callback_object || !g_streaming_complete_method || !g_is_streaming.load()) {
        return;
    }
    
    JNIEnv* env;
    if (g_vm->AttachCurrentThread(&env, nullptr) != JNI_OK) {
        LOGe("Failed to attach to Java thread for completion callback");
        return;
    }
    
    jstring jResponse = env->NewStringUTF(fullResponse.c_str());
    env->CallVoidMethod(g_callback_object, g_streaming_complete_method, jResponse);
    env->DeleteLocalRef(jResponse);
    
    // Reset streaming flag
    g_is_streaming.store(false);
    
    // Detach if needed
    if (env->ExceptionCheck()) {
        env->ExceptionClear();
    }
}

extern "C"
JNIEXPORT jboolean JNICALL
Java_com_example_local_1llm_1plugin_LocalLlmPlugin_loadModel(JNIEnv *env, jobject, jstring filename) {
    LOGi("JNI loadModel called");
    logModelState("LOAD_MODEL_START");
    llama_model_params model_params = llama_model_default_params();

    auto path_to_model = env->GetStringUTFChars(filename, 0);
    LOGi("Loading model from %s", path_to_model);

    model = llama_model_load_from_file(path_to_model, model_params);
    env->ReleaseStringUTFChars(filename, path_to_model);

    if (!model) {
        LOGe("load_model() failed - model is null");
        return JNI_FALSE;
    }
    LOGi("load_model() succeeded");

    int n_threads = std::max(1, std::min(8, (int) sysconf(_SC_NPROCESSORS_ONLN) - 2));
    LOGi("Using %d threads", n_threads);

    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = 2048;
    ctx_params.n_threads = n_threads;
    ctx_params.n_threads_batch = n_threads;

    context = llama_new_context_with_model(model, ctx_params);

    if (!context) {
        LOGe("llama_new_context_with_model() returned null)");
        llama_model_free(model);
        model = nullptr;
        return JNI_FALSE;
    }

    // Initialize batch
    batch = llama_batch_init(512, 0, 1);

    // Initialize sampler
    auto sparams = llama_sampler_chain_default_params();
    sparams.no_perf = true;
    sampler = llama_sampler_chain_init(sparams);
    llama_sampler_chain_add(sampler, llama_sampler_init_greedy());

    llama_log_set(log_callback, NULL);
    
    logModelState("LOAD_MODEL_COMPLETE");

    return JNI_TRUE;
}

extern "C"
JNIEXPORT void JNICALL
Java_com_example_local_1llm_1plugin_LocalLlmPlugin_freeModel(JNIEnv *, jobject) {
    LOGi("=== FREE MODEL CALLED ===");
    logModelState("FREE_MODEL_START");
    
    if (sampler) {
        llama_sampler_free(sampler);
        sampler = nullptr;
    }
    if (batch.token) {
        llama_batch_free(batch);
        batch = {0, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr};
    }
    if (context) {
        llama_free(context);
        context = nullptr;
    }
    if (model) {
        llama_model_free(model);
        model = nullptr;
    }
    llama_backend_free();
    
    logModelState("FREE_MODEL_COMPLETE");
}

extern "C"
JNIEXPORT jstring JNICALL
Java_com_example_local_1llm_1plugin_LocalLlmPlugin_generateResponse(JNIEnv *env, jobject, jstring prompt) {
    LOGi("JNI generateResponse called");
    if (!model || !context || !sampler) {
        LOGe("Model not loaded");
        return env->NewStringUTF("Error: Model not loaded");
    }

    const auto text = env->GetStringUTFChars(prompt, 0);
    LOGi("Generating response for: %s", text);

    // Tokenize the prompt - disable chat template to get single response
    const auto tokens_list = common_tokenize(context, text, true, false);

    // COMPLETE memory reset: Clear everything to prevent context contamination
    // Each request should be treated as a separate conversation
    llama_memory_t mem = llama_get_memory(context);
    llama_memory_clear(mem, true);  // Clear both metadata AND data

    // Process the prompt
    common_batch_clear(batch);
    for (size_t i = 0; i < tokens_list.size(); i++) {
        common_batch_add(batch, tokens_list[i], i, { 0 }, false);
    }
    batch.logits[batch.n_tokens - 1] = true;

    if (llama_decode(context, batch) != 0) {
        LOGe("llama_decode() failed");
        env->ReleaseStringUTFChars(prompt, text);
        return env->NewStringUTF("Error: Decode failed");
    }

    // Generate response - simple loop
    std::string response;
    cached_token_chars.clear();

    const auto vocab = llama_model_get_vocab(model);
    for (int i = 0; i < g_current_token_limit.load(); i++) { // Dynamic smart limit
        const auto new_token_id = llama_sampler_sample(sampler, context, batch.n_tokens - 1);

        if (llama_vocab_is_eog(vocab, new_token_id)) {
            break;
        }

        auto new_token_chars = common_token_to_piece(context, new_token_id);
        cached_token_chars += new_token_chars;

        if (is_valid_utf8(cached_token_chars.c_str())) {
            response += cached_token_chars;
            cached_token_chars.clear();
        }

        // Add token to batch for next iteration
        common_batch_clear(batch);
        common_batch_add(batch, new_token_id, tokens_list.size() + i, { 0 }, true);

        if (llama_decode(context, batch) != 0) {
            LOGe("llama_decode() failed during generation");
            break;
        }
    }

    env->ReleaseStringUTFChars(prompt, text);

    // Extract everything after "A:" and stop at first sentence
    size_t a_pos = response.find("A:");
    std::string generated_response = "I'm sorry, I couldn't generate a proper response.";

    if (a_pos != std::string::npos) {
        size_t start = a_pos + strlen("A:");
        if (start < response.length()) {
            generated_response = response.substr(start);

            // Remove leading whitespace
            size_t first = generated_response.find_first_not_of(" \t\n\r");
            if (first != std::string::npos) {
                generated_response = generated_response.substr(first);
            }

            // Stop at first sentence ending (just the first one)
            size_t period = generated_response.find_first_of(".!?");
            if (period != std::string::npos) {
                generated_response = generated_response.substr(0, period + 1);
            }
            // No over-complication - just return what we got
        }
    }

    // Split response from thoughts/explanation BEFORE truncating to first sentence
    std::string full_response = response.substr(a_pos != std::string::npos ? a_pos + 3 : 0);

    // Remove leading whitespace from full response
    size_t first_non_ws = full_response.find_first_not_of(" \t\n\r");
    if (first_non_ws != std::string::npos) {
        full_response = full_response.substr(first_non_ws);
    }

    std::string main_response = full_response;
    std::string ai_thoughts = "";

    // Look for explanation marker in full response (before sentence truncation)
    size_t explain_pos = full_response.find("**Explanation:**");
    if (explain_pos != std::string::npos) {
        // Main response is everything before explanation
        main_response = full_response.substr(0, explain_pos);
        // Trim ending whitespace
        main_response = main_response.substr(0, main_response.find_last_not_of(" \t\n\r") + 1);

        // AI thoughts are everything after explanation
        ai_thoughts = full_response.substr(explain_pos);
    }

    // Now truncate main_response to first sentence if needed
    size_t period_pos = main_response.find_first_of(".!?\n");
    if (period_pos != std::string::npos) {
        main_response = main_response.substr(0, period_pos + 1);
    }

    // Format as JSON-like string: main_response|ai_thoughts
    std::string combined_response = main_response + "|" + ai_thoughts;

    LOGi("Main response: '%s'", main_response.c_str());
    if (!ai_thoughts.empty()) {
        LOGi("AI Thoughts found (%zu chars)", ai_thoughts.length());
    }

    return env->NewStringUTF(combined_response.c_str());
}

// Set up streaming callbacks
extern "C"
JNIEXPORT void JNICALL
Java_com_example_local_1llm_1plugin_LocalLlmPlugin_setStreamingCallbacks(JNIEnv *env, jobject obj) {
    LOGi("Setting up streaming callbacks");
    
    // Store JavaVM pointer for thread management
    env->GetJavaVM(&g_vm);
    
    // Create global reference to callback object
    g_callback_object = env->NewGlobalRef(obj);
    
    // Find callback methods
    jclass callbackClass = env->GetObjectClass(obj);
    g_send_token_method = env->GetMethodID(callbackClass, "onTokenReceived", "(Ljava/lang/String;)V");
    g_streaming_complete_method = env->GetMethodID(callbackClass, "onStreamingComplete", "(Ljava/lang/String;)V");
    
    env->DeleteLocalRef(callbackClass);
    
    if (!g_send_token_method || !g_streaming_complete_method) {
        LOGe("Failed to find streaming callback methods");
    } else {
        LOGi("Streaming callbacks successfully set up");
    }
}

// True streaming generation with callbacks (Phase 3: C++ Classification Integration)
// JNI CONTRACT: Native C++ handles all question classification and token limits
extern "C"
JNIEXPORT void JNICALL
Java_com_example_local_1llm_1plugin_LocalLlmPluginKt_generateResponseStreaming(JNIEnv *env, jobject, jstring prompt, jint maxTokens) {
    LOGi("JNI generateResponseStreaming called - Native C++ classification active");
    logModelState("STREAMING_GENERATION_START");
    
    if (!model || !context || !sampler) {
        LOGe("Model not loaded");
        completeStreamingToJava("Error: Model not loaded");
        return;
    }
    
    // Set streaming flag
    g_is_streaming.store(true);
    
    const auto text = env->GetStringUTFChars(prompt, 0);
    std::string promptText(text);
    LOGi("Starting native classification streaming for: %s", text);

    // PHASE 3: Classify question in C++ for optimal performance
    auto classifyStart = std::chrono::high_resolution_clock::now();
    QuestionType qType = classifyQuestion(promptText);
    int smartTokens = getTokenLimitForQuestionType(qType);
    auto classifyEnd = std::chrono::high_resolution_clock::now();
    auto classifyDuration = std::chrono::duration_cast<std::chrono::microseconds>(classifyEnd - classifyStart);
    
    // CRITICAL: Native classification ALWAYS takes precedence over Flutter parameters
    g_current_token_limit.store(smartTokens);
    
    // COMPREHENSIVE QA LOGGING FOR VERIFICATION
    LOGi("=== SMART LIMITS QA VERIFICATION ===");
    LOGi("Question: '%s'", text);
    LOGi("Classification Result: %s", getQuestionTypeName(qType));
    LOGi("Token Limit Applied: %d tokens (native C++ determination)", smartTokens);
    LOGi("Classification Performance: %lld microseconds", classifyDuration.count());
    LOGi("Flutter maxTokens Parameter: %d (SUPERSEDED by native classification)", maxTokens);
    LOGi("Response Expectation: %d tokens (exceeds 50-token requirement)", smartTokens);
    LOGi("Architecture: Native C++ classification with smart token limits");
    LOGi("=== END QA LOG ===");
    
    // Tokenize the prompt
    const auto tokens_list = common_tokenize(context, text, true, false);

    // Clear memory
    llama_memory_t mem = llama_get_memory(context);
    llama_memory_clear(mem, true);

    // Process the prompt
    common_batch_clear(batch);
    for (size_t i = 0; i < tokens_list.size(); i++) {
        common_batch_add(batch, tokens_list[i], i, { 0 }, false);
    }
    batch.logits[batch.n_tokens - 1] = true;

    if (llama_decode(context, batch) != 0) {
        LOGe("llama_decode() failed");
        env->ReleaseStringUTFChars(prompt, text);
        completeStreamingToJava("Error: Decode failed");
        return;
    }

    // Generate tokens and stream them via callbacks
    const auto vocab = llama_model_get_vocab(model);
    std::string full_response;
    cached_token_chars.clear();

    for (int i = 0; i < g_current_token_limit.load(); i++) { // Using C++ classification result
        // Check if streaming was cancelled
        if (!g_is_streaming.load()) {
            LOGi("Streaming cancelled by user");
            break;
        }
        
        const auto new_token_id = llama_sampler_sample(sampler, context, batch.n_tokens - 1);

        if (llama_vocab_is_eog(vocab, new_token_id)) {
            LOGi("Generated EOS token at step %d", i);
            break;
        }

        auto new_token_chars = common_token_to_piece(context, new_token_id);
        cached_token_chars += new_token_chars;

        // Send complete UTF-8 tokens immediately via callback
        if (is_valid_utf8(cached_token_chars.c_str())) {
            std::string token_to_send = cached_token_chars;
            full_response += token_to_send;
            cached_token_chars.clear();
            
            // Send token via callback (non-blocking)
            sendTokenToJava(token_to_send);
            
            // Small delay for better UX (remove if performance is critical)
            usleep(10000); // 10ms delay between tokens
        }

        // Add token to batch for next iteration
        common_batch_clear(batch);
        common_batch_add(batch, new_token_id, tokens_list.size() + i, { 0 }, true);

        if (llama_decode(context, batch) != 0) {
            LOGe("llama_decode() failed during streaming generation");
            break;
        }
    }

    env->ReleaseStringUTFChars(prompt, text);
    LOGi("Phase 3 streaming generation complete, length: %zu, tokens used: %d", full_response.length(), g_current_token_limit.load());
    
    // Send complete response via callback
    completeStreamingToJava(full_response);
}

// Cleanup streaming callbacks
extern "C"
JNIEXPORT void JNICALL
Java_com_example_local_1llm_1plugin_LocalLlmPlugin_cleanupStreamingCallbacks(JNIEnv *env, jobject) {
    LOGi("Cleaning up streaming callbacks");
    
    g_is_streaming.store(false);
    
    if (g_callback_object) {
        env->DeleteGlobalRef(g_callback_object);
        g_callback_object = nullptr;
    }
    
    g_send_token_method = nullptr;
    g_streaming_complete_method = nullptr;
}

extern "C"
JNIEXPORT void JNICALL
Java_com_example_local_1llm_1plugin_LocalLlmPluginKt_setTokenLimit(JNIEnv *env, jobject, jint limit) {
    g_current_token_limit.store(limit);
    LOGi("Token limit set to: %d", limit);
}

extern "C"
JNIEXPORT jstring JNICALL
Java_com_example_local_1llm_1plugin_LocalLlmPlugin_getPlatformVersion(JNIEnv *env, jobject) {
    LOGi("JNI getPlatformVersion called - library is loaded!");
    return env->NewStringUTF("Android (LLM ready - Native loaded)");
}
