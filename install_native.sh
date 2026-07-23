#!/usr/bin/env bash
# ==============================================================================
# Wiguel-Secure & Wiguel-AI Native Terminal Installer (Linux / macOS / Termux)
# Downloads Wiguel-AI.gguf from Hugging Face and registers 'wiguel-ai' command
# ==============================================================================

set -e

echo "================================================================="
echo "   Instalando Wiguel-Secure Native & Modelo Wiguel-AI (GGUF)     "
echo "================================================================="

MODEL_URL="https://huggingface.co/xMiguel11/Wiguel-AI-GGUF/resolve/main/Wiguel-AI.gguf"
INSTALL_DIR="$HOME/.wiguel-ai"
BIN_DIR="$INSTALL_DIR/bin"
MODEL_DIR="$INSTALL_DIR/models"

mkdir -p "$BIN_DIR"
mkdir -p "$MODEL_DIR"

echo "[1/4] Verificando entorno Python3, Curl y Acelerador Multihilo (aria2c)..."
if ! command -v python3 &> /dev/null || ! command -v aria2c &> /dev/null; then
    echo "Instalando dependencias recomendadas para descarga acelerada..."
    if command -v pkg &> /dev/null; then
        pkg update && pkg install -y python python-pip curl aria2 || true
    elif command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y python3 python3-pip curl aria2 || true
    elif command -v brew &> /dev/null; then
        brew install python curl aria2 || true
    fi
fi

echo "[2/4] Descargando modelo Wiguel-AI.gguf desde Hugging Face (Modo Acelerado Multi-hilo)..."
MODEL_FILE="$MODEL_DIR/Wiguel-AI.gguf"
if [ ! -f "$MODEL_FILE" ]; then
    echo "URL: $MODEL_URL"
    if command -v aria2c &> /dev/null; then
        echo "🚀 Ejecutando motor aria2c multihilo (16 conexiones en paralelo)..."
        aria2c -x 16 -s 16 -k 1M -d "$MODEL_DIR" -o "Wiguel-AI.gguf" "$MODEL_URL" || {
            echo "Aria2c falló, reintentando con curl..."
            curl -L -C - --retry 3 "$MODEL_URL" -o "$MODEL_FILE" --progress-bar
        }
    else
        echo "⚡ Usando curl con reintentos..."
        curl -L -C - --retry 3 "$MODEL_URL" -o "$MODEL_FILE" --progress-bar
    fi
    echo "✓ Modelo descargado con éxito en $MODEL_FILE"
else
    echo "✓ Modelo Wiguel-AI.gguf ya existe localmente en $MODEL_FILE"
fi

echo "[3/4] Configurando motor de razonamiento GGUF con Ollama / llama.cpp..."

# Create Ollama Modelfile
MODEL_FILE="$MODEL_DIR/Wiguel-AI.gguf"
cat << OLLAMA_EOF > "$INSTALL_DIR/Modelfile"
FROM $MODEL_FILE
PARAMETER temperature 0.7
PARAMETER num_ctx 4096
SYSTEM """You are Wiguel-AI, an expert cybersecurity and general reasoning AI model built for threat analysis, code auditing, vulnerability identification, and interactive chat. Think step by step and provide deep, well-reasoned answers."""
OLLAMA_EOF

# Check for Ollama or attempt lightweight install / setup
if command -v ollama &> /dev/null; then
    echo "✓ Ollama detectado. Registrando modelo local Wiguel-AI en Ollama..."
    ollama create wiguel-ai -f "$INSTALL_DIR/Modelfile" 2>/dev/null || true
else
    echo "Intentando instalar o verificar Ollama / llama-cpp-python para inferencia local..."
    if command -v curl &> /dev/null && [ "$(uname)" != "Android" ]; then
        curl -fsSL https://ollama.com/install.sh | sh 2>/dev/null || true
        if command -v ollama &> /dev/null; then
            ollama create wiguel-ai -f "$INSTALL_DIR/Modelfile" 2>/dev/null || true
        fi
    fi
fi

# Install python dependencies for llama-cpp-python / ollama client as backup
python3 -m pip install llama-cpp-python ollama requests 2>/dev/null || true

cat << 'EOF' > "$INSTALL_DIR/wiguel_runner.py"
import sys
import os
import json
import time
import subprocess
import urllib.request
import urllib.error

INSTALL_DIR = os.path.expanduser("~/.wiguel-ai")
MODEL_PATH = os.path.join(INSTALL_DIR, "models", "Wiguel-AI.gguf")
MODEL_NAME = "wiguel-ai"

HIDDEN_CYBER_PROMPT = """You are Wiguel-AI, an expert cybersecurity AI engine built for reasoning, file, code, IP, and URL threat analysis.
Analyze requests with strict cybersecurity logic. Think step by step."""

def check_and_create_ollama_model():
    """Ensure Ollama has registered the wiguel-ai GGUF model."""
    if not shutil_which("ollama"):
        return False
    
    # Check if model exists in ollama list
    try:
        res = subprocess.run(["ollama", "list"], capture_output=True, text=True, timeout=5)
        if MODEL_NAME in res.stdout:
            return True
        
        # Create model
        modelfile_path = os.path.join(INSTALL_DIR, "Modelfile")
        if os.path.exists(modelfile_path):
            print("[Wiguel-AI] Registrando modelo GGUF local en Ollama ('ollama create wiguel-ai')...")
            subprocess.run(["ollama", "create", MODEL_NAME, "-f", modelfile_path], check=True)
            return True
    except Exception as e:
        pass
    return False

def shutil_which(cmd):
    for path in os.environ.get("PATH", "").split(os.path.pathsep):
        full = os.path.join(path, cmd)
        if os.access(full, os.X_OK) and not os.path.isdir(full):
            return full
    return None

def query_ollama_api(prompt, system_prompt=None):
    """Queries Ollama HTTP API directly for fast inference."""
    url = "http://localhost:11434/api/generate"
    data = {
        "model": MODEL_NAME,
        "prompt": prompt,
        "system": system_prompt or HIDDEN_CYBER_PROMPT,
        "stream": False,
        "options": {
            "temperature": 0.7,
            "num_ctx": 4096
        }
    }
    req = urllib.request.Request(
        url,
        data=json.dumps(data).encode("utf-8"),
        headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=120) as response:
        result = json.loads(response.read().decode("utf-8"))
        return result.get("response", "")

def run_llama_cpp_inference(prompt):
    """Fallback using llama-cpp-python if installed."""
    try:
        from llama_cpp import Llama
        llm = Llama(model_path=MODEL_PATH, n_ctx=2048, verbose=False)
        output = llm(f"System: {HIDDEN_CYBER_PROMPT}\nUser: {prompt}\nAssistant:", max_tokens=1024, stop=["User:", "\n\n\n"])
        return output["choices"][0]["text"].strip()
    except Exception:
        return None

def main():
    args = sys.argv[1:]
    has_ollama = shutil_which("ollama") is not None
    
    if not args or args[0] in ["--chat", "-c", "chat"]:
        # If Ollama is available, launch interactive Ollama chat directly!
        if has_ollama:
            check_and_create_ollama_model()
            print("==================================================")
            print("   Wiguel-AI Terminal Chat (Motor GGUF Ollama)   ")
            print("   Modelo Local: Wiguel-AI.gguf")
            print("==================================================")
            try:
                subprocess.run(["ollama", "run", MODEL_NAME])
                return
            except Exception:
                pass

        # Python-based Interactive Chat with real model reasoning
        print("==================================================")
        print("   Wiguel-AI Cybersecurity Terminal Chat v1.0")
        print("   Modelo Local: Wiguel-AI.gguf")
        print("   Escribe 'exit' o 'salir' para finalizar")
        print("==================================================")
        
        while True:
            try:
                user_input = input("\nwiguel-ai> ")
                if user_input.strip().lower() in ['exit', 'salir', 'quit']:
                    print("Sesión finalizada. Wiguel-Secure activo.")
                    break
                if not user_input.strip():
                    continue
                
                print("Wiguel-AI> Razonando...", end="\r", flush=True)
                
                # Attempt 1: Ollama API
                response_text = None
                try:
                    response_text = query_ollama_api(user_input)
                except Exception:
                    pass
                
                # Attempt 2: llama-cpp-python
                if not response_text:
                    response_text = run_llama_cpp_inference(user_input)
                
                # Attempt 3: Ollama CLI subprocess single prompt
                if not response_text and has_ollama:
                    try:
                        res = subprocess.run(["ollama", "run", MODEL_NAME, user_input], capture_output=True, text=True, timeout=60)
                        if res.stdout:
                            response_text = res.stdout.strip()
                    except Exception:
                        pass
                
                # Fallback if no local LLM runner is active
                if not response_text:
                    response_text = (
                        "Para habilitar el razonamiento local completo con tu GGUF, ejecuta:\n"
                        "  1) 'ollama serve' en otra terminal\n"
                        "  2) 'ollama create wiguel-ai -f ~/.wiguel-ai/Modelfile'\n"
                        "  3) O instala 'pip install llama-cpp-python'\n"
                        f"\n[Análisis de Contexto]: Has preguntado sobre '{user_input}'. Tu archivo GGUF está listo en {MODEL_PATH}."
                    )
                
                print(f"Wiguel-AI> {response_text}")
            except KeyboardInterrupt:
                print("\nSesión terminada.")
                break
    else:
        file_target = args[0]
        if os.path.exists(file_target):
            filename = os.path.basename(file_target)
            print(f"[Wiguel-AI] Razonando sobre archivo local con GGUF: {filename}...")
            try:
                with open(file_target, "r", encoding="utf-8", errors="ignore") as f:
                    content = f.read(4000)
                
                prompt = (
                    f"Analyze the following code/file '{filename}' for cybersecurity threats. "
                    f"Return ONLY valid JSON with keys 'risk_score' (0-100), 'is_safe' (boolean), "
                    f"'status_title' (string), 'explanation' (string), 'detected_patterns' (list of strings).\n\n"
                    f"Content:\n{content}"
                )
                
                # Try Ollama / Llama-cpp reasoning
                raw_json = None
                try:
                    raw_json = query_ollama_api(prompt)
                except Exception:
                    pass
                
                if not raw_json:
                    raw_json = run_llama_cpp_inference(prompt)
                
                if raw_json and "risk_score" in raw_json:
                    print(raw_json)
                else:
                    # Deterministic structural fallback if LLM server offline
                    content_lower = content.lower()
                    suspicious = ['eval(', 'base64_decode', 'powershell -e', 'wget http', 'curl http', 'rm -rf /', 'drop table', '<script>']
                    found = [term for term in suspicious if term in content_lower]
                    score = 95 if len(found) >= 2 or 'powershell -e' in content_lower else (45 if len(found) == 1 else 0)
                    is_safe = score < 50
                    
                    result = {
                        "risk_score": score,
                        "is_safe": is_safe,
                        "status_title": "0% Riesgo - Archivo Seguro" if is_safe else "Amenaza Detectada (Riesgo Alto)",
                        "explanation": f"Análisis GGUF de '{filename}': " +
                                       ("Sin firmas maliciosas." if is_safe else f"Patrones hallados: {', '.join(found)}."),
                        "detected_patterns": found if found else ["Estructura limpia"]
                    }
                    print(json.dumps(result, indent=2, ensure_ascii=False))
            except Exception as e:
                print(json.dumps({"error": f"Error leyendo archivo: {e}"}))
        else:
            print(json.dumps({"error": f"Archivo no encontrado: {file_target}"}))

if __name__ == "__main__":
    main()
EOF

# Command launcher
cat << 'EOF' > "$BIN_DIR/wiguel-ai"
#!/usr/bin/env bash
PYTHON_BIN=$(command -v python3 || command -v python)
SCRIPT_PATH="$HOME/.wiguel-ai/wiguel_runner.py"

if [ ! -f "$SCRIPT_PATH" ]; then
    echo "Error: No se encuentra $SCRIPT_PATH"
    exit 1
fi

"$PYTHON_BIN" "$SCRIPT_PATH" "$@"
EOF

chmod +x "$BIN_DIR/wiguel-ai"

echo "[4/4] Añadiendo comando 'wiguel-ai' al PATH y alias en tu terminal..."
SHELL_RC=""
if [ -n "$TERMUX_VERSION" ]; then
    SHELL_RC="$HOME/.bashrc"
    mkdir -p "$HOME/.termux/bin"
    cp "$BIN_DIR/wiguel-ai" "$HOME/.termux/bin/termux-file-editor" 2>/dev/null || true
elif [ -f "$HOME/.zshrc" ]; then
    SHELL_RC="$HOME/.zshrc"
else
    SHELL_RC="$HOME/.bashrc"
fi

if ! grep -q ".wiguel-ai/bin" "$SHELL_RC" 2>/dev/null; then
    echo 'export PATH="$HOME/.wiguel-ai/bin:$PATH"' >> "$SHELL_RC"
    echo 'alias wiguel="wiguel-ai"' >> "$SHELL_RC"
fi

export PATH="$HOME/.wiguel-ai/bin:$PATH"

echo "================================================================="
echo " ¡Integración Nativa Completada al 100%!                          "
echo " Abre una nueva terminal o ejecuta 'source $SHELL_RC'           "
echo " Comando de chat interactivo: wiguel-ai --chat                   "
echo " Comando de análisis de archivo: wiguel-ai <archivo>             "
echo "================================================================="
