# Changelog

## [Unreleased]
- Scaffold: multi-stage Vulkan Dockerfile (IFM fork @ 42adf01), `models.json`
  manifest (0.9B/3.7B/7B × 6 quants), `ollama` shim CLI, supervisor
  entrypoint, compose, Unraid template (port 11436), docs, CI.
- Build fixes: unified `llama` binary (no `llama-server` target anymore),
  `glslc` + `spirv-headers` deps, shared impl libs installed flat.
- **SIGILL fix:** build with `GGML_NATIVE=OFF` (AVX2 baseline). The CI
  runner's `-march=native` baked AVX-512 into the image, crashing any
  host without it (Ryzen 3700X, i5-14600K) with exit 132 — even before
  a model was loaded. Verified `zmm=0` + clean start on the published
  image.
- CLI: added `stop` (unload → bare API); `rm` unloads the active model
  first instead of refusing.
- Verified on build host (CPU): pull, run→restart→load, `/health`,
  `/v1/models`, `/v1/chat/completions` (OpenAI shape incl.
  `reasoning_content`), list/ps/show/stop/rm, REPL, model re-run.
- Pending Tower verification: runtime ladder 0.9B → 3.7B → 7B on Arc A380
  with `/dev/dri` Vulkan (tokens/s, VRAM, stability) not yet run.
- Open: replace restart-switching with `/models/load` by-name if proven
  reliable on hardware; `/api/*` shim only if a real consumer needs it.
