# Deployment

Two independent services. You can ship the first one today for nothing; the
second is the one that costs money.

| | What it does | Where it runs | Cost |
|---|---|---|---|
| **Previews** | Stills of the user in each of the 40 styles | Gemini API | **Free** (~500 img/day) |
| **Render** | The 5-second Wan 2.2 Animate video | Your GPU / RunPod | ~$0.05–0.60 per clip |

This split is deliberate. Free previews are what convince someone to pay; the
expensive render only ever runs *after* the paywall.

---

## Answering "where do I run this?"

Your PC can't, and neither can any free tier, run Wan 2.2 Animate 14B properly.
The model needs **24 GB VRAM minimum** (fp8) and 48–80 GB is where it's
comfortable. For reference:

| Option | GPU | Free? | Verdict |
|---|---|---|---|
| Google Colab (free) | T4 16 GB | Yes | **Won't fit.** 14B fp8 alone is ~14 GB before the text encoder |
| Kaggle | T4×2 / P100 16 GB | 30 h/wk | **Won't fit** for a single 14B model |
| Lightning AI | T4 16 GB | ~15 credits/mo | Same VRAM wall |
| **RunPod Serverless** | 4090 24 GB → H100 80 GB | No | **Recommended.** Scales to zero, per-second billing |
| RunPod Pod (on-demand) | 4090 / A100 / H100 | No | Best for *developing* the workflow — you get a live ComfyUI UI |
| Modal | A100 / H100 | Starter credits | Good alternative, per-second billing |

**Realistic numbers.** A 5-second clip takes ~3–8 min on an H100 (~$2.50/hr
on-demand, ~$0.99/hr spot) → roughly **$0.25–0.60 per clip**. On a 4090 at
~$0.34–0.69/hr it is slower but cheaper per clip. At the 39 kr (~$3.60) price
point in the paywall, the margin is fine.

**The genuinely free path to try it:** rent a RunPod 4090 pod for one hour
(≈$0.50), prove the workflow end to end, export it, then shut the pod down.
That is the cheapest way to find out whether the output quality is good enough
before committing to anything.

---

## 1. Previews (free) — do this first

1. Get a key at <https://aistudio.google.com/apikey>. No credit card.
2. Run the API anywhere cheap (a $5 VPS, Fly.io, Render, or your laptop):

```bash
cd backend
pip install -r requirements.txt
export GEMINI_API_KEY=...           # the only required variable
export API_KEY=$(openssl rand -hex 24)   # what the app sends as a Bearer token
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

3. Point the app at it:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000 \
            --dart-define=API_KEY=<the same key>
```

`10.0.2.2` is how the Android emulator reaches your host. On a real device use
your machine's LAN IP.

Previews now generate in the background the moment the user takes their photo,
and the picker fills in with their actual face. `/v1/renders` will return 503
until ComfyUI exists — that is expected and the app falls back to mock renders.

Free-tier limits change; check
<https://ai.google.dev/gemini-api/docs/rate-limits> before launch. 40 previews
per user against a ~500/day quota means roughly **12 new users per day** on the
free tier — fine for testing, not for launch. Budget for the paid tier or
generate previews lazily (only the visible category).

---

## 2. Render — RunPod

### Step 1: prove the workflow on a Pod (not serverless)

Serverless has no UI, so build the graph interactively first.

1. RunPod → Deploy a **Pod**, RTX 4090 or A100, template *RunPod PyTorch 2.7*.
2. Attach a **Network Volume** (100 GB) mounted at `/workspace`. The models are
   ~70 GB — putting them on a volume means you download them once, ever.
3. In the pod's terminal:

```bash
cd /workspace
wget https://raw.githubusercontent.com/<your-repo>/main/backend/scripts/provision_comfy.sh
bash provision_comfy.sh /workspace
cd /workspace/ComfyUI && python main.py --listen 0.0.0.0 --port 8188
```

4. Open the pod's port 8188 in a browser. Build and run a Wan 2.2 Animate graph
   until you get a clip you like.

### Step 2: mark the nodes and export

In the ComfyUI canvas, right-click → **Title** on each of these and rename:

| Node | Title | Required |
|---|---|---|
| `LoadImage` (the user's face) | `FY_INPUT_IMAGE` | yes |
| positive `CLIPTextEncode` | `FY_POSITIVE` | yes |
| the save/video-combine node | `FY_OUTPUT` | yes |
| negative `CLIPTextEncode` | `FY_NEGATIVE` | no |
| `KSampler` | `FY_SAMPLER` | no |
| the node with width/height/length | `FY_LATENT` | no |

Then **Workflow → Export (API)** — the plain "Save" format is not queueable —
and save it as `backend/workflows/wan22_animate.json`, replacing the starter.

Verify without a GPU:

```bash
python -m pytest tests/test_workflow.py -q
```

> **The shipped `wan22_animate.json` is a starter, not a guarantee.** It is a
> standard Wan image-to-video graph wired to the models the provision script
> downloads, and it passes structural validation — but node names and inputs
> shift between ComfyUI and custom-node versions, and the Animate pipeline adds
> pose/detection steps. Treat step 1 as required, not optional. `GET /v1/health`
> tells you whether the file on disk is bindable.

### Step 3: deploy serverless

```bash
docker build -t <you>/funnyyou-worker:1 backend/
docker push <you>/funnyyou-worker:1
```

RunPod → Serverless → New Endpoint:

- Container image: `<you>/funnyyou-worker:1`
- Network volume: the same one, mounted at `/workspace`
- GPU: 24 GB (4090) or 80 GB (H100) — start with 80 GB, drop it once you know
  the clip fits
- Idle timeout: 5 s. Max workers: 1 while testing.

Env vars: `COMFY_DIR=/workspace/ComfyUI`, `COMFY_URL=http://127.0.0.1:8188`.

Cold start is 60–120 s because ComfyUI has to load 14 B of weights. Keep one
worker warm if that is unacceptable — it costs idle GPU time, so probably not
worth it until you have real traffic.

---

## Configuration reference

| Variable | Default | Notes |
|---|---|---|
| `PREVIEW_PROVIDER` | `gemini` | `gemini`, `pollinations`, `none` |
| `VIDEO_PROVIDER` | `comfy` | `comfy`, `pollinations`, `none` |
| `POLLINATIONS_API_KEY` | — | Enables hosted stills and video |
| `POLLINATIONS_VIDEO_MODEL` | `wan-fast` | `wan`, `seedance-pro`, `veo`, … |
| `POLLINATIONS_IMAGE_MODEL` | `nanobanana` | `kontext`, `seedream`, … |
| `COMFY_URL` | `http://127.0.0.1:8188` | Where ComfyUI listens |
| `COMFY_WORKFLOW` | `wan22_animate.json` | File under `workflows/` |
| `COMFY_TIMEOUT_S` | `1800` | Hard cap on one render |
| `GEMINI_API_KEY` | — | Unset disables previews |
| `API_KEY` | — | Unset disables auth (local only) |
| `PUBLIC_BASE_URL` | `http://127.0.0.1:8000` | Must be reachable *by the phone* |
| `OUTPUT_DIR` | `./data/outputs` | Rendered mp4s |
| `VIDEO_SECONDS` / `VIDEO_FPS` | `5` / `16` | Frame count is forced to 4n+1 |
| `VIDEO_WIDTH` / `VIDEO_HEIGHT` | `480` / `832` | Portrait. 720p costs ~3× |

## Health check

```bash
curl -s localhost:8000/v1/health | python -m json.tool
```

```json
{
  "ready": true,
  "videoProvider": "comfy",
  "videoEnabled": true,
  "comfyReachable": true,
  "workflowValid": true,
  "previewProvider": "gemini",
  "previewsEnabled": true,
  "previewError": null,
  "authRequired": true
}
```

`ready` tracks the *paid* path only. Previews are a nice-to-have — without them
the app falls back to its designed artwork and still sells videos.

`ready: false` tells you exactly which half is broken before you waste a render.

## Before you take real money

- [ ] Rate-limit `/v1/renders` per device — a render costs you real GPU time
- [ ] Verify the App Store receipt server-side; right now credits are
      client-side and trivially spoofable
- [ ] Move outputs to S3/R2 with expiring URLs instead of local disk
- [ ] Add NSFW/consent checks on uploaded faces — you are putting real people's
      likenesses into generated video, which carries obvious abuse potential
- [ ] Set a spend cap on the RunPod endpoint
