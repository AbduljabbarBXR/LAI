# 🤖 Model Download Instructions

Your Local AI App needs these **large model files** to run (excluded from Git for size):

## 📥 **Required Model Files**

### **1. Gemma 3B (Primary Model)**
- **File**: `gemma-3-1B-it-QAT-Q4_0.gguf`
- **Size**: ~687MB
- **Download**: [Hugging Face - Gemma 3B GGUF](https://huggingface.co/barbato/gemma-2-2b-gguf/resolve/main/gemma-3-1b-it-q4_0.gguf)

### **2. TinyLlama (Backup Model)**
- **File**: `tinyllama-1.1b-chat-v1.0-q4_k_m.gguf`
- **Size**: ~637MB
- **Download**: [Hugging Face - TinyLlama GGUF](https://huggingface.co/PY007/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/TinyLlama-1.1B-Chat-v1.0-q4_k_m.gguf)

## 📁 **Installation Steps**

1. **Create models directory**:
   ```bash
   mkdir -p assets/models/
   ```

2. **Download models** (place both files in `assets/models/`):
   ```
   assets/
   └── models/
       ├── gemma-3-1B-it-QAT-Q4_0.gguf
       └── tinyllama-1.1b-chat-v1.0-q4_k_m.gguf
   ```

3. **Run the app** - models will load automatically!

## 🎯 **Alternative Models**
- **Phi-2**: Smaller, faster model (300MB)
- **Code Llama**: For programming assistance (1GB)
- **Mistral**: High-quality general model (800MB)

## 📊 **Performance Notes**
- **Initial load**: ~30-60 seconds per model
- **RAM usage**: ~2-4GB when loaded
- **Inference speed**: ~10-20 tokens/second

Your app is ready to provide **100% offline AI chat** with enterprise-grade streaming performance! 🚀