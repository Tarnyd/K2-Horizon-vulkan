# Changelog

## [Unreleased]
- Scaffold: multi-stage Vulkan Dockerfile (IFM fork @ 42adf01), `models.json`
  manifest (0.9B/3.7B/7B × 6 quants), `ollama` shim CLI, supervisor
  entrypoint, compose, Unraid template (port 11436), docs, CI.
- Pending Tower verification: compile OK expected; runtime ladder
  0.9B → 3.7B → 7B on Arc A380 (tokens/s, VRAM, stability) not yet run.
- Open: replace restart-switching with `/models/load` by-name if proven
  reliable on hardware; `/api/*` shim only if a real consumer needs it.
