# RunPod Serverless worker: ComfyUI + Wan 2.2 Animate + the render handler.
#
# Build this WITHOUT the models (they are ~70 GB) and mount a RunPod network
# volume at /workspace instead — see DEPLOYMENT.md. Baking models into the
# image makes cold starts and image pulls painful.

FROM runpod/pytorch:2.7.0-py3.11-cuda12.8.1-devel-ubuntu22.04

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    COMFY_DIR=/workspace/ComfyUI \
    COMFY_URL=http://127.0.0.1:8188

RUN apt-get update -qq && \
    apt-get install -y -qq git wget ffmpeg libgl1 libglib2.0-0 && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY app ./app
COPY workflows ./workflows
COPY scripts ./scripts
COPY runpod_handler.py .

RUN chmod +x scripts/*.sh

# The handler boots ComfyUI itself on first request, so the container has a
# single job: stay alive and serve.
CMD ["python", "-u", "runpod_handler.py"]
