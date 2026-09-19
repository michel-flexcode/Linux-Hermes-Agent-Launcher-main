#!/usr/bin/env bash
set -euo pipefail

REPO_ID="${REPO_ID:-ornith-ai/Ornith-1.5-35B-A3B-GGUF}"
TARGET_DIR="${MODEL_DIR:-${MODEL_DIR:-$HOME/.local/models}}"
ALLOW_PATTERNS="${ALLOW_PATTERNS:-*.gguf}"
PYTHON_BIN="${PYTHON_BIN:-python3}"

log() { printf '%s\n' "[$(date +%H:%M:%S)] $*"; }
fail() { printf '%s\n' "[$(date +%H:%M:%S)] ERROR: $*" >&2; exit 1; }

require_python() {
  command -v "$PYTHON_BIN" >/dev/null 2>&1 || fail "Python 3 is required to download the GGUF model from Hugging Face."
}

ensure_hf_hub() {
  "$PYTHON_BIN" - <<'PY'
import importlib.util, os, subprocess, sys
spec = importlib.util.find_spec('huggingface_hub')
if spec is not None:
    raise SystemExit(0)

cmd = [sys.executable, '-m', 'pip', 'install', '--quiet', 'huggingface_hub']
try:
    subprocess.check_call(cmd)
except subprocess.CalledProcessError:
    fallback = [sys.executable, '-m', 'pip', 'install', '--quiet', '--break-system-packages', 'huggingface_hub']
    subprocess.check_call(fallback)
PY
}

main() {
  require_python
  ensure_hf_hub

  mkdir -p "$TARGET_DIR"
  log "Téléchargement du modèle Ornith depuis Hugging Face : $REPO_ID"
  log "Dossier cible : $TARGET_DIR"

  "$PYTHON_BIN" - <<PY
import os
from pathlib import Path
from huggingface_hub import snapshot_download

repo_id = os.environ.get('REPO_ID', 'ornith-ai/Ornith-1.5-35B-A3B-GGUF')
allow = os.environ.get('ALLOW_PATTERNS', '*.gguf')
target_dir = os.environ.get('MODEL_DIR', os.path.join(os.path.expanduser('~'), '.local', 'models'))

os.makedirs(target_dir, exist_ok=True)
try:
    snapshot_download(repo_id=repo_id, allow_patterns=[allow], local_dir=target_dir)
except Exception:
    pass

found = sorted(str(p) for p in Path(target_dir).rglob('*.gguf'))
if found:
    print('FOUND:' + '\n'.join(found))
else:
    print('FOUND:')
PY

  local_files=()
  while IFS= read -r f; do
    local_files+=("$f")
  done < <(find "$TARGET_DIR" -type f -name '*.gguf' 2>/dev/null | head -n 20)

  if [[ ${#local_files[@]} -eq 0 ]]; then
    echo
    log "Aucun fichier .gguf trouvé dans le dépôt $REPO_ID."
    log "Le repo Hugging Face indiqué contient des fichiers .safetensors, pas des GGUF compatibles avec llama.cpp."
    log "Pour un usage avec llama.cpp, il faut soit :"
    log "  1) télécharger un GGUF déjà quantifié depuis un dépôt qui publie .gguf, ou"
    log "  2) convertir le modèle HF en GGUF avec llama.cpp (convert_hf_to_gguf.py)."
    log "Exemple de conversion :"
    log "  git clone https://github.com/ggerganov/llama.cpp"
    log "  python3 llama.cpp/convert_hf_to_gguf.py <chemin_du_repo_hf> --outtype q4_k_m --outfile $TARGET_DIR/Ornith-1.5-35B-A3B-Q4_K_M.gguf"
    fail "Le dépôt Hugging Face fourni n’est pas directement utilisable comme modèle GGUF pour llama.cpp."
  fi

  log "Fichiers .gguf présents :"
  find "$TARGET_DIR" -type f -name '*.gguf' -print | head -n 20

  echo
  log "Le modèle est dans : $TARGET_DIR"
  log "Tu peux maintenant lancer le service avec ./launch.sh install ou ./scripts/llama-ornith-serve.sh install"
}

main "$@"
