#!/usr/bin/env bash
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
URL="${LLM_API_BASE_URL:-http://127.0.0.1:8080}"
API_TIMEOUT="${API_TIMEOUT:-20}"
MODEL_NAME="${MODEL_FILENAME:-Ornith-1.5-35B-A3B-Q4_K_M.gguf}"

log(){ echo "[$(date +%H:%M:%S)] $*"; }
fail(){ echo "[$(date +%H:%M:%S)] ERROR: $*" >&2; exit 1; }

if ! command -v curl >/dev/null 2>&1; then
  fail "curl est requis pour valider l'API locale."
fi

if ! command -v python3 >/dev/null 2>&1; then
  fail "python3 est requis pour parser la réponse JSON de l'API."
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
MODELS_FILE="$WORKDIR/models.json"
CHAT_FILE="$WORKDIR/chat.json"

log "Validation de l'API OpenAI-compatible sur $URL"
MODELS_CODE="$(curl -sS --max-time "$API_TIMEOUT" -o "$MODELS_FILE" -w '%{http_code}' "$URL/v1/models" || true)"
if [[ "$MODELS_CODE" != "200" ]]; then
  fail "GET $URL/v1/models a retourné HTTP $MODELS_CODE; le backend n'est pas prêt."
fi

MODEL_ID="$(python3 - "$MODELS_FILE" <<'PY'
import json, sys
path = sys.argv[1]
try:
    with open(path, 'r', encoding='utf-8') as fh:
        data = json.load(fh)
    for item in data.get('data', []):
        if isinstance(item, dict) and item.get('id'):
            print(item['id'])
            break
except Exception:
    pass
PY
)"

if [[ -z "$MODEL_ID" ]]; then
  MODEL_ID="$MODEL_NAME"
fi

PAYLOAD="$(MODEL_ID="$MODEL_ID" python3 - <<'PY'
import json, os
payload = {
    'model': os.environ['MODEL_ID'],
    'messages': [{'role': 'user', 'content': 'ping'}],
    'max_tokens': 8,
    'temperature': 0,
}
print(json.dumps(payload))
PY
)"

CHAT_CODE="$(curl -sS --max-time "$API_TIMEOUT" -H 'Content-Type: application/json' -o "$CHAT_FILE" -w '%{http_code}' -d "$PAYLOAD" "$URL/v1/chat/completions" || true)"
if [[ "$CHAT_CODE" != "200" ]]; then
  echo "--- /v1/models payload ---" >&2
  cat "$MODELS_FILE" >&2 || true
  echo "--- /v1/chat/completions payload ---" >&2
  cat "$CHAT_FILE" >&2 || true
  fail "POST $URL/v1/chat/completions a retourné HTTP $CHAT_CODE; le backend est installé mais pas encore serviceable."
fi

log "OK: /v1/models HTTP $MODELS_CODE et /v1/chat/completions HTTP $CHAT_CODE"
log "Modèle utilisé pour la validation: $MODEL_ID"
