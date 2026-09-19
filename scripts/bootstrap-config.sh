#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_TEMPLATE="$ROOT/config/.env.example"
DEFAULT_ENV="$ROOT/config/.env"

usage() {
  cat <<'EOF'
Usage: ./scripts/bootstrap-config.sh [--env-file PATH] [--template PATH] [--model-dir PATH]

Validates and writes a coherent environment file for the llama.cpp backend.
It ensures the model path and filename match a real GGUF file, keeps CTX_SIZE
compatible with the Hermes requirement, and writes a consistent .env file.
EOF
}

ENV_FILE="$DEFAULT_ENV"
TEMPLATE_FILE="$DEFAULT_TEMPLATE"
MODEL_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="${2:-}"
      shift 2
      ;;
    --template)
      TEMPLATE_FILE="${2:-}"
      shift 2
      ;;
    --model-dir)
      MODEL_DIR="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$MODEL_DIR" ]]; then
  # Default to the project config value when available, otherwise the standard model path.
  if [[ -f "$TEMPLATE_FILE" ]]; then
    MODEL_DIR="$(grep -E '^MODEL_DIR=' "$TEMPLATE_FILE" | sed 's/^MODEL_DIR=//')"
  fi
  if [[ -z "$MODEL_DIR" ]]; then
    MODEL_DIR="/opt/models"
  fi
fi

if [[ ! -f "$TEMPLATE_FILE" ]]; then
  echo "ERROR: template not found: $TEMPLATE_FILE" >&2
  exit 1
fi

mkdir -p "$(dirname "$ENV_FILE")"
cp "$TEMPLATE_FILE" "$ENV_FILE"

# Normalize the model directory.
MODEL_DIR="${MODEL_DIR%/}"
if [[ -n "$MODEL_DIR" ]]; then
  mkdir -p "$MODEL_DIR"
  sed -i "s|^MODEL_DIR=.*|MODEL_DIR=$MODEL_DIR|" "$ENV_FILE"
fi

# Prefer a real GGUF file if a model is already present.
GGUF_FILE=""
if compgen -G "$MODEL_DIR/*.gguf" > /dev/null; then
  GGUF_FILE="$(basename "$(ls -1 "$MODEL_DIR"/*.gguf | head -n 1)")"
fi

# If the env already contains MODEL_FILENAME and it is valid, keep it.
if [[ -n "$GGUF_FILE" ]]; then
  sed -i "s|^MODEL_FILENAME=.*|MODEL_FILENAME=$GGUF_FILE|" "$ENV_FILE"
fi

# Force the Hermes-compatible defaults and ensure they remain coherent.
if ! grep -Eq '^LISTEN_PORT=' "$ENV_FILE"; then
  echo 'LISTEN_PORT=8080' >> "$ENV_FILE"
fi
sed -i 's|^LISTEN_PORT=.*|LISTEN_PORT=8080|' "$ENV_FILE"

if ! grep -Eq '^CTX_SIZE=' "$ENV_FILE"; then
  echo 'CTX_SIZE=73728' >> "$ENV_FILE"
fi
sed -i 's|^CTX_SIZE=.*|CTX_SIZE=73728|' "$ENV_FILE"

# Ensure the configured GGUF matches the actual downloaded model when present.
if [[ -n "$GGUF_FILE" ]]; then
  if ! grep -Eq "^MODEL_FILENAME=$GGUF_FILE$" "$ENV_FILE"; then
    sed -i "s|^MODEL_FILENAME=.*|MODEL_FILENAME=$GGUF_FILE|" "$ENV_FILE"
  fi
  if [[ ! -f "$MODEL_DIR/$GGUF_FILE" ]]; then
    echo "ERROR: configured GGUF is missing: $MODEL_DIR/$GGUF_FILE" >&2
    exit 1
  fi
fi

# Hard-fail if a bad or non-GGUF model is configured.
if grep -Eq '^MODEL_FILENAME=' "$ENV_FILE"; then
  CURRENT_MODEL="$(grep '^MODEL_FILENAME=' "$ENV_FILE" | cut -d= -f2-)"
  if [[ -n "$CURRENT_MODEL" && "$CURRENT_MODEL" != *.gguf ]]; then
    echo "ERROR: MODEL_FILENAME must end with .gguf: $CURRENT_MODEL" >&2
    exit 1
  fi
fi

# Keep the env file consistent for the service layer.
printf 'OK: generated coherent .env at %s\n' "$ENV_FILE"
printf 'MODEL_DIR=%s\nMODEL_FILENAME=%s\nLISTEN_PORT=8080\nCTX_SIZE=73728\n' "$MODEL_DIR" "$(grep '^MODEL_FILENAME=' "$ENV_FILE" | cut -d= -f2-)"
