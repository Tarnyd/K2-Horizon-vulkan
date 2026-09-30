#!/bin/bash
# Supervisor entrypoint: keeps llama-server running for the model named in
# the state file. `ollama run <other>` writes a new state + SIGTERMs the
# server; this loop restarts it with the new model. No docker socket needed.
set -e

STATE_DIR="${STATE_DIR:-/root/.k2-horizon}"
STATE_FILE="$STATE_DIR/active-model"
PORT="${PORT:-11436}"

mkdir -p "$STATE_DIR"
# /dev/dri visibility log (GPU debug aid, mirrors ollama-intel-gpu habit)
if [ -e /dev/dri ]; then
  echo "[entrypoint] /dev/dri present: $(ls /dev/dri | tr '\n' ' ')"
else
  echo "[entrypoint] WARNING: /dev/dri not found - Vulkan has no GPU. Re-run with --device=/dev/dri." >&2
fi

# Boot model: state file (from a previous `run`) wins, else MODEL_ALIAS env,
# else serve the API with no model loaded (use `ollama run ...` to load one).
if [ ! -f "$STATE_FILE" ] && [ -n "${MODEL_ALIAS:-}" ]; then
  echo "$MODEL_ALIAS" > "$STATE_FILE"
fi

while true; do
  ALIAS="$(cat "$STATE_FILE" 2>/dev/null || true)"
  echo "[entrypoint] starting server (model: ${ALIAS:-none})"
  # shellcheck disable=SC2086
  if ollama _run-server $ALIAS; then
    CODE=0
  else
    CODE=$?
  fi
  echo "[entrypoint] server exited (code $CODE), restarting in 5s..."
  sleep 5
done
