# =============================================================================
# K2-Horizon on Intel Arc GPUs via Vulkan (llama-server, Ollama-compatible)
# =============================================================================
# Builds llama-server from the MBZUAI-IFM llama.cpp fork (branch with K2
# Horizon architecture support) with the Vulkan backend, plus a small
# `ollama`-style CLI (pull/run/list/ps) and a model alias manifest.
#
# Why Vulkan and not SYCL/oneAPI: needs only a C++ compiler (no oneAPI
# toolchain), builds in ~15-30 min, and runs on Arc via Mesa ANV / Intel ICD
# with /dev/dri from the host. Why the fork and not upstream: upstream
# llama.cpp has NOT merged k2-horizon yet (ggml-org/llama.cpp#28361 open) —
# when it does, flip LLAMACPP_REPO to ggml-org/llama.cpp.
#
# Florence of versions (all pinned, all overridable):
#   docker build --build-arg LLAMACPP_REF=<sha> -t k2-horizon-vulkan .
# =============================================================================

# ---------------------------------------------------------------------------
# Pinned sources — bump when the fork moves or upstream merges k2-horizon
# ---------------------------------------------------------------------------
ARG LLAMACPP_REPO=MBZUAI-IFM/llama.cpp
# model/K2Horizon @ 2026-09-17 (first K2-complete state: arch + templates +
# pre-tokenizer). Re-pin to a newer SHA (or ggml-org/llama.cpp master once
# k2-horizon lands there) to pick up fixes.
ARG LLAMACPP_REF=42adf019f76013dac873b5b43950d54d5ab27216
ARG UBUNTU_TAG=24.04

# ---------------------------------------------------------------------------
# Stage 1: build llama-server with Vulkan backend
# ---------------------------------------------------------------------------
FROM ubuntu:${UBUNTU_TAG} AS builder
ARG LLAMACPP_REPO
ARG LLAMACPP_REF
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install --no-install-recommends -y \
        ca-certificates git cmake ninja-build pkg-config \
        build-essential libvulkan-dev glslc spirv-headers python3 && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone --no-checkout "https://github.com/${LLAMACPP_REPO}.git" llamacpp && \
    cd llamacpp && \
    git fetch --depth 1 origin "${LLAMACPP_REF}" && \
    git checkout "${LLAMACPP_REF}" && \
    git log -1 --pretty='%H %ad %s' --date=short

WORKDIR /src/llamacpp
# Unified `llama` binary (llama serve/cli/... subcommands).
# CPU backend is always built too (fallback + host testability).
# NOTE: executables land in per-target dirs (only *libraries* go to
# build/bin), so locate the binary instead of assuming its path.
RUN cmake -S . -B build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DGGML_VULKAN=ON \
        -DGGML_NATIVE=OFF \
        -DLLAMA_BUILD_TESTS=OFF \
        -DLLAMA_BUILD_EXAMPLES=OFF \
        -DLLAMA_BUILD_SERVER=ON && \
    cmake --build build --target llama-app -j"$(nproc)" && \
    mkdir -p /out /out/lib && \
    cp "$(find build -name llama -type f -executable | head -1)" /out/llama && \
    cp build/bin/*.so* /out/lib/ && \
    ls /out/ && ls /out/lib/ | head -20 && \
    (/out/llama --version || echo "note: --version probe failed, continuing")

# ---------------------------------------------------------------------------
# Stage 2: slim runtime (Vulkan loader + Intel ANV ICD + CLI)
# ---------------------------------------------------------------------------
FROM ubuntu:${UBUNTU_TAG} AS runtime
ARG LLAMACPP_REF
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Etc/UTC \
    LLAMACPP_REF="${LLAMACPP_REF}"

LABEL org.opencontainers.image.title="K2-Horizon on Intel Arc GPUs (Vulkan, Ollama-compatible)" \
      org.opencontainers.image.description="llama-server (K2 Horizon fork, Vulkan backend) with Ollama-style CLI + OpenAI-compatible API for Intel Arc GPUs." \
      org.opencontainers.image.licenses="MIT"

RUN apt-get update && \
    apt-get install --no-install-recommends -y \
        ca-certificates curl python3 \
        libvulkan1 mesa-vulkan-drivers \
        libgomp1 && \
    rm -rf /var/lib/apt/lists/*

# Server binary + shared impl libs + wrapper files
# (.so files go flat into /usr/local/lib, which is on the default loader
# path - no LD_LIBRARY_PATH games needed)
COPY --from=builder /out/llama /usr/local/bin/llama
COPY --from=builder /out/lib/ /usr/local/lib/
COPY models.json /etc/k2-horizon/models.json
COPY scripts/ollama /usr/local/bin/ollama
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/ollama /usr/local/bin/entrypoint.sh && \
    mkdir -p /models && \
    ldconfig && \
    /usr/local/bin/llama --version

# Server env (all overridable). PORT is internal; publish it (default 11436).
# MODEL_ALIAS selects boot model, e.g. k2-horizon-7b:Q4_K_M (empty = serve API only).
ENV OLLAMA_HOST=0.0.0.0:11436 \
    PORT=11436 \
    MODELS_DIR=/models \
    MODEL_ALIAS="" \
    CTX_SIZE=8192 \
    CTX_SIZE_7B=4096 \
    N_GPU_LAYERS=999 \
    OLLAMA_ORIGINS="*"

EXPOSE 11436
VOLUME ["/models", "/root/.k2-horizon"]

HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD curl -fsS http://127.0.0.1:${PORT:-11436}/health || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["serve"]
