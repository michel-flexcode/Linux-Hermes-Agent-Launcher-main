#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LAUNCHER="$ROOT/launch.sh"
HELPER="$ROOT/scripts/download-ornith-model.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[[ -f "$HELPER" ]] || fail 'Model download helper is missing.'
rg -q 'ornith-ai/Ornith-1.5-35B-A3B-GGUF' "$HELPER" || fail 'Download script must target the actual Ornith GGUF repo.'
rg -q 'huggingface_hub|snapshot_download' "$HELPER" || fail 'Download script must use Hugging Face hub to fetch the GGUF.'
rg -q '\*\.gguf|allow_patterns' "$HELPER" || fail 'Download script must filter for .gguf files.'
rg -q -- '--break-system-packages|externally-managed' "$HELPER" || fail 'Download script must handle Debian/Ubuntu PEP 668 restrictions.'
rg -q 'Aucun fichier \.gguf trouvé|n’est pas directement utilisable comme modèle GGUF|convert_hf_to_gguf' "$HELPER" || fail 'Script must explain the real GGUF conversion requirement clearly.'
rg -q 'model[[:space:]]*Open the interactive launcher menu|model[[:space:]]*Download the Ornith GGUF model' "$LAUNCHER" || fail 'Launcher help does not mention the model download command.'

printf 'PASS: model download flow is available and documented.\n'
