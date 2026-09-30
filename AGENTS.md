# AGENTS.md — working agreement for AI agents in this repo

K2-Horizon-vulkan: llama-server (IFM fork, Vulkan) + Ollama-style CLI for
Intel Arc. Public-safe, generic, anonymous: no names, emails, IPs, tokens.

## 1. Repo map

- `Dockerfile` — multi-stage: builder compiles `llama-server` from
  `LLAMACPP_REPO` @ `LLAMACPP_REF` with `GGML_VULKAN=ON`; runtime is slim
  Ubuntu + Vulkan loader + Mesa ANV + python3 + CLI. Sources are args —
  keep them pinned (SHA, not branch).
- `models.json` — alias manifest: family → repo + exact GGUF filenames per
  quant + size estimates + ctx defaults. NOTE the 1B/4B/7B file naming vs
  0.9B/3.7B/7B marketing — never hand-type filenames elsewhere, read them
  from here (the CLI does).
- `scripts/ollama` — Python stdlib-only CLI (run/pull/list/ps/rm/show +
  hidden `_run-server`). No third-party deps, ever.
- `entrypoint.sh` — supervisor loop: serves model from state file; CLI
  switches models via state + SIGTERM (no docker socket). Keep POSIX-ish.
- `docker-compose.yml`, `ollama-k2horizon.xml` (Unraid, port 11436),
  `.env.example`, `README.md`, `CHANGELOG.md`.

## 2. Golden rules

1. **Source pins.** `LLAMACPP_REF` must be a full SHA. To update: set the
   SHA, rebuild, smoke-test, record old→new + reason in CHANGELOG. If
   upstream merges k2-horizon, prefer `LLAMACPP_REPO=ggml-org/llama.cpp`.
2. **Vulkan-only leanness.** Never add oneAPI/Level-Zero/Mesa-compute
   stacks — Vulkan (+ ANV from `mesa-vulkan-drivers`) is the whole GPU
   story. Builder needs `libvulkan-dev` + `glslang-tools` (glslc); runtime
   needs `libvulkan1` + `mesa-vulkan-drivers` + `libgomp1`.
3. **CLI stays stdlib-only.** No pip packages in the image or the shim.
4. **One model at a time.** Server lifecycle = state file + SIGTERM +
   entrypoint loop. Don't invent daemon protocols; if `/models/load`
   by-name proves reliable on hardware, it may replace restart-switching
   (open question, verify on Tower before refactoring).
5. **Small diffs, public-safe.** Same as always: no secrets, no local paths
   outside `/mnt/user/appdata/...` examples and named volumes.

## 3. Verified facts (don't re-derive without cause)

- Fork `model/K2Horizon` @ `42adf01` (2026-09-17): K2 arch = MoE experts +
  MoVA value-routing built from standard ops (`argsort_top_k`, `get_rows`,
  shared `build_lora_mm_id`, shared `build_attn`) — all implemented by
  `ggml-vulkan`. No custom shaders needed (verified in source).
- Server surface: `/health`, `/v1/models|chat/completions|completions|
  embeddings`, `/models/load|unload`, `-hf/--hf-file` auto-download,
  `--alias/--ctx-size/--n-gpu-layers` flags confirmed in fork source.
- GGUF filenames: 0.9B repo uses `K2-Horizon-1B-*`, 3.7B repo uses
  `K2-Horizon-4B-*`, 7B repo uses `K2-Horizon-7B-*`.
- Upstream #28361 OPEN (2026-09-29): fork remains the only source.

## 4. Build / test

```bash
docker build -t tarnyd/k2-horizon-vulkan:test .        # ~15-30 min (builder)
docker run -d --name k2t --device=/dev/dri -p 11436:11436 \
  -v k2t-models:/models tarnyd/k2-horizon-vulkan:test  # needs Intel GPU host
docker exec -it k2t ollama run k2-horizon-0.9b "Hej!"  # ladder: 0.9B, 3.7B, 7B
curl http://localhost:11436/v1/models
docker rm -f k2t
```

- No Intel GPU on build host: only verify compile + CLI unit paths
  (`list` on empty dir, bad-alias errors, `--help`-ish usage).
- Never commit `.env`, `*.gguf`, `*.log`.

## 5. Definition of done

- Image builds from pinned SHA; CLI commands behave per README.
- 0.9B→3.7B→7B ladder verified on Arc (tokens/s noted in CHANGELOG).
- README + CHANGELOG updated; Unraid XML well-formed; git clean.
