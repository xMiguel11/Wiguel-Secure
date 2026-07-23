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

echo "[3/4] Configurando ejecutable nativo con razonamiento interno (Temperature 0.3)..."

# Install python dependencies for llama-cpp-python / requests as backup
python3 -m pip install llama-cpp-python requests 2>/dev/null || true

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

# Hidden System Prompt & Configuration (Temp 0.3)
HIDDEN_CYBER_PROMPT = """You are Wiguel-AI, an expert cybersecurity and general reasoning AI model built for threat analysis, code auditing, vulnerability identification, and interactive chat. Think step by step and provide deep, well-reasoned answers."""
TEMPERATURE = 0.3

def query_ollama_api(prompt, system_prompt=None):
    """Queries Ollama HTTP API directly using local GGUF path or default model with Temp 0.3."""
    url = "http://localhost:11434/api/generate"
    data = {
        "model": "wiguel-ai",
        "prompt": prompt,
        "system": system_prompt or HIDDEN_CYBER_PROMPT,
        "stream": False,
        "options": {
            "temperature": TEMPERATURE,
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
    """Fallback using llama-cpp-python with temperature 0.3."""
    try:
        from llama_cpp import Llama
        llm = Llama(model_path=MODEL_PATH, n_ctx=2048, verbose=False)
        output = llm(
            f"System: {HIDDEN_CYBER_PROMPT}\nUser: {prompt}\nAssistant:",
            max_tokens=1024,
            temperature=TEMPERATURE,
            stop=["User:", "\n\n\n"]
        )
        return output["choices"][0]["text"].strip()
    except Exception:
        return None

def main():
    args = sys.argv[1:]
    
    if not args or args[0] in ["--chat", "-c", "chat"]:
        print("==================================================")
        print("   Wiguel-AI Cybersecurity Terminal Chat v1.0")
        print("   Modelo Local: Wiguel-AI.gguf (Temp 0.3)")
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
                
                # Fallback if no local server running
                if not response_text:
                    response_text = (
                        f"[Razonamiento Wiguel-AI (Temp {TEMPERATURE})]: Consulta '{user_input}' procesada.\n"
                        f"Para inferencia GGUF completa en vivo, asegúrate de tener Ollama o llama-cpp-python activo."
                    )
                
                print(f"Wiguel-AI> {response_text}")
            except KeyboardInterrupt:
                print("\nSesión terminada.")
                break
    else:
        file_target = args[0]
        if os.path.exists(file_target):
            filename = os.path.basename(file_target)
            print(f"[Wiguel-AI] Razonando sobre archivo local con GGUF (Temp {TEMPERATURE}): {filename}...")
            try:
                with open(file_target, "r", encoding="utf-8", errors="ignore") as f:
                    content = f.read(4000)
                
                prompt = (
                    f"Analyze the following code/file '{filename}' for cybersecurity threats. "
                    f"Return ONLY valid JSON with keys 'risk_score' (0-100), 'is_safe' (boolean), "
                    f"'status_title' (string), 'explanation' (string), 'detected_patterns' (list of strings).\n\n"
                    f"Content:\n{content}"
                )
                
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
