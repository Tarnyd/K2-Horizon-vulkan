# K2-Horizon on Intel Arc GPUs (Vulkan, Ollama-style)

Run [IFM K2-Horizon](https://huggingface.co/IFM) models (0.9B / 3.7B / 7B)
on Intel Arc GPUs with an Ollama-style UX — because neither upstream
llama.cpp nor Ollama supports the `k2-horizon` architecture yet
([llama.cpp#28361](https://github.com/ggml-org/llama.cpp/issues/28361) open).

**What this is:** the unified `llama` binary (`llama serve` ...) built from the
[MBZUAI-IFM llama.cpp fork](https://github.com/MBZUAI-IFM/llama.cpp)
(branch `model/K2Horizon`) with the Vulkan backend, plus a small `ollama`
CLI (`run`/`pull`/`list`/`ps`/`rm`/`show`) and an OpenAI-compatible API.
Drop-in *replacement feel* for everyday Ollama use — not a byte-identical
Ollama clone (see [Differences from Ollama](#differences-from-ollama)).

**Status: experimental.** The K2 support itself is pre-release quality
(IFM's words). If upstream merges `k2-horizon`, this rebuilds from upstream
(one-line `LLAMACPP_REPO`/`LLAMACPP_REF` change).

Docker Hub: **`tarnyd/k2-horizon-vulkan`** (after first publish)

```bash
docker pull tarnyd/k2-horizon-vulkan:latest
```

## Quickstart (Unraid / Linux with Intel Arc)

Requires `/dev/dri` on the host (i915/xe driver) and ~10 GB free for models.

**Unraid (recommended — no build, image is pulled from Docker Hub):**
Docker → Add Container → Template, paste the raw URL of
`ollama-k2horizon.xml` from this repo. The template installs the container
as `k2-horizon` on port 11436 with `--device=/dev/dri` and model storage
under `/mnt/user/appdata/k2-horizon-models`. It runs beside Ollama (own
port and storage) by design. Then, from any terminal with Docker access:

```bash
docker exec -it k2-horizon ollama run k2-horizon-7b:Q4_K_M "Hej!"
```

**Plain Docker (any Linux host):**

```bash
docker run -d --name k2-horizon \
  --device=/dev/dri \
  -p 11436:11436 \
  -v k2-models:/models -v k2-state:/root/.k2-horizon \
  tarnyd/k2-horizon-vulkan:latest

# pull + load + chat (downloads ~4.6 GB on first run):
docker exec -it k2-horizon ollama run k2-horizon-7b:Q4_K_M "Hej!"
```

Building locally is only for development: `docker compose up -d --build`
(or `./scripts/build.sh`) on a build machine — never needed on the server.

## Model aliases

`k2-horizon-{0.9b,3.7b,7b}[:QUANT]`, default quant `Q4_K_M`
(case-insensitive). Note the repos name files `1B`/`4B`/`7B` while families
are marketed `0.9B`/`3.7B`/`7B` — the manifest maps it, you never type it.

| Alias | HF repo | Default file | Size | Fits 6 GB Arc |
|---|---|---|---|---|
| `k2-horizon-0.9b` | IFM/K2-Horizon-0.9B-GGUF | `K2-Horizon-1B-Q4_K_M.gguf` | ~0.7 GB | ✅ fully |
| `k2-horizon-3.7b` | IFM/K2-Horizon-3.7B-GGUF | `K2-Horizon-4B-Q4_K_M.gguf` | ~2.6 GB | ✅ fully |
| `k2-horizon-7b` | IFM/K2-Horizon-7B-GGUF | `K2-Horizon-7B-Q4_K_M.gguf` | ~4.6 GB | ✅ at ctx 4K |

Other quants per family: `Q5_0`, `Q5_K_M`, `Q6_K`, `Q8_0`, `BF16`
(see `models.json`; sizes are estimates until verified on hardware).
Example: `ollama run k2-horizon-3.7b:Q5_K_M`.

Set a boot model with `MODEL_ALIAS=k2-horizon-0.9b` (downloads on first
boot), or leave empty for API-only until you `run` something.

## CLI reference (`docker exec -it k2-horizon ollama ...`)

- `run <alias> ["prompt"]` — pull if needed, load (restarts server), then
  chat REPL (or single prompt). This is the everyday command.
- `pull <alias>` — download only.
- `list` — downloaded GGUFs (+ `LOADED` mark).
- `ps` — active + server-loaded models, server status.
- `show <alias>` — repo/file/size/loaded/ctx info.
- `stop` — unload the active model (server restarts bare, frees VRAM).
- `rm <alias>` — delete local file (unloads first if it is the active model).

## API

Native server endpoints on port 11436 (unified `llama serve` binary):

- `GET /health`, `GET /v1/models`, `POST /v1/chat/completions`
  (streaming supported), `POST /v1/completions`, `POST /v1/embeddings`
- `POST /models/load`, `/models/unload` (advanced)

Point OpenAI-compatible clients (Open WebUI custom endpoint, Hindsight
`openai` provider with `BASE_URL=http://<host>:11436/v1`, `curl`) at it.
K2 models emit chain-of-thought into `reasoning_content` before the answer
in `content` — give clients enough `max_tokens` (256+) or the visible
answer may be cut off.

## Thinking control

K2 is a reasoning model: the chat template defaults to `effort=high`,
which can burn thousands of tokens before answering (or never stop).

- `REASONING_BUDGET` (default `1024`): hard cap on thinking tokens per
  reply — the model then answers immediately. `-1` = unlimited (old
  runaway behavior), `256` = snappy but dumber.
- `REASONING=off`: no thinking at all (fastest). `on`/`auto` = model
  default.
- Per request (OpenAI body): `reasoning_effort: "none"` or
  `reasoning_budget_tokens: N` override the server default for that one
  call. Efforts `high`/`medium`/`low` exist upstream, but only `high`
  extracts cleanly today — `medium`/`low` leak template markers into the
  visible answer.

## Differences from Ollama (known gaps)

- No native `/api/*` endpoints (`/api/chat`, `/api/tags`, …). Clients
  speaking pure Ollama-native API need a shim (planned only if a real
  consumer requires it — Hindsight/Open WebUI work via OpenAI endpoints).
- One model served at a time; `run <other>` restarts the server (~10–30 s
  reload). No parallel-model serving, no `Modelfile`s, no `keep_alive`
  tuning (server flag parity differs).
- Context defaults are conservative for 6 GB VRAM (8K, 7B: 4K);
  override with `CTX_SIZE` / `CTX_SIZE_7B`. The models natively support
  far larger contexts — unusable on this class of card.
- Pre-release model support: expect rough edges; inference bugs belong
  upstream (IFM fork → llama.cpp), not here.

## What's inside

- **Base:** Ubuntu 24.04; runtime needs only Vulkan loader + Mesa ANV ICD
  (`mesa-vulkan-drivers`) + `/dev/dri` from the host. No oneAPI, no Intel
  compute stack — Vulkan build needs just a C++ compiler.
- **Server:** unified `llama` binary (`llama serve`) from
  `MBZUAI-IFM/llama.cpp` @ pinned SHA
  (see `Dockerfile` `LLAMACPP_REF`), `GGML_VULKAN=ON`.
- **Why Vulkan works for K2:** the MoVA implementation composes standard
  ops (`argsort_top_k`, `get_rows`, shared `lora_mm` MoE helper, standard
  attention) — all already implemented by `ggml-vulkan` (verified in
  source 2026-09-30). No custom shaders were needed.

## Updating

- **New fork fixes / upstream merge:** bump `LLAMACPP_REF` (and
  `LLAMACPP_REPO` to `ggml-org/llama.cpp` if k2-horizon lands upstream),
  rebuild, smoke-test the 0.9B→3.7B→7B ladder, push.
- **New K2 models/quants:** extend `models.json` (repo + exact filename).

## Troubleshooting

- `ollama run` hangs at load / OOM: lower ctx (`CTX_SIZE=4096`,
  `CTX_SIZE_7B=2048`), drop to a smaller quant, or use the 3.7B family.
- `library`/GPU doubts: this image has no Ollama discovery — check
  `docker logs k2-horizon` for Vulkan device lines from llama-server, and
  compare tokens/s against CPU (`N_GPU_LAYERS=0` forces CPU for A/B).
- `/dev/dri` missing → Vulkan finds no devices; server still starts
  (CPU fallback inside ggml) but slow. Fix `--device=/dev/dri`.

## License

MIT — see [LICENSE](LICENSE). llama.cpp is MIT; K2-Horizon weights are
Apache-2.0 (IFM). Weights are downloaded at runtime, never redistributed
in the image.
