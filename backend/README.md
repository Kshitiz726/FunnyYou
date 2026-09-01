# Funny You — backend

Two services behind one FastAPI app.

```
POST   /v1/renders        multipart(image, prompt, template_id) -> job    [paid]
GET    /v1/renders/{id}   poll: status, stage, progress, etaSeconds
DELETE /v1/renders/{id}   cancel
GET    /v1/videos/{file}  the finished mp4
POST   /v1/previews       multipart(image, scenarios) -> base64 stills    [free]
GET    /v1/health         is ComfyUI up, is the workflow bindable
```

`/v1/previews` runs on Gemini's free image tier. `/v1/renders` drives ComfyUI
with Wan 2.2 Animate on a GPU. See [DEPLOYMENT.md](DEPLOYMENT.md) for where to
run each and what it costs.

## Run it locally

The dev stack boots the real API plus local stand-ins for the two things that
cost money — no GPU, no API key, nothing to sign up for:

```bash
pip install -r requirements-dev.txt
python -m devstack.run
```

Then in another terminal:

```bash
python scripts/verify_stack.py   # health + previews + a full render to mp4
pytest -q                        # 42 tests
```

`verify_stack.py` writes what it got back to `data/verify/` so you can open the
JPEGs and play the MP4.

The stand-ins speak the real wire protocols, so everything in `app/` runs
unmodified against them. Swap in the real services one at a time — the stack
leaves alone whatever you have already pointed somewhere real:

```bash
GEMINI_API_KEY=<real key> python -m devstack.run   # real previews, fake render
COMFY_URL=http://<pod>:8188 python -m devstack.run # real render, fake previews
```

To run only the API against real services:

```bash
export GEMINI_API_KEY=...        # without it previews return 503
uvicorn app.main:app --reload --port 8000
```

## Layout

```
app/
  main.py             HTTP surface
  config.py           env-var settings, no secret defaults
  providers/          who runs the AI - the only vendor-aware code
    base.py           ImageProvider / VideoProvider, Asset, ProviderError
    gemini.py         free face-referenced stills
    pollinations.py   keyed stills + video (wan, seedance, veo)
    comfy.py          your own GPU - the RunPod path
  comfy_client.py     ComfyUI HTTP + websocket client
  workflow.py         binds app inputs into a ComfyUI graph, by node title
  render_service.py   one render, photo -> file, with staged progress
  preview_service.py  batches previews over an ImageProvider
  jobs.py             in-process job registry
workflows/
  wan22_animate.json  starter graph — replace with your proven export
devstack/             local stand-ins, dev only — never shipped
  fake_comfy.py       ComfyUI's HTTP + websocket protocol, real playable mp4
  fake_gemini.py      Gemini's generateContent shape, real jpeg
  media.py            face compositing and H.264 encoding
  run.py              boots all three services
scripts/
  provision_comfy.sh  ComfyUI + models on a fresh GPU box
  verify_stack.py     end-to-end check against a running stack
  check_providers.py  calls the real vendor APIs with your keys
  probe_comfy.py      drives a real ComfyUI box end to end
runpod_handler.py     RunPod Serverless entry point
```

The fakes are not mocks — they validate the graph the way ComfyUI does (missing
`class_type`, dangling node references, an image name that was never uploaded)
and emit the same websocket sequence, so a workflow-binding mistake fails
locally exactly as it would on a rented GPU.

## Providers — who actually runs the AI

Two env vars pick the vendor. Nothing above `app/providers/` knows which one is
in use, so moving to RunPod later is a config change, not a rewrite.

```bash
PREVIEW_PROVIDER=gemini|pollinations|comfy|none   # default gemini
VIDEO_PROVIDER=comfy|pollinations|none            # default comfy
```

| Provider | Does | Key | Cost |
|---|---|---|---|
| `gemini` | Face-referenced stills | [aistudio.google.com/apikey](https://aistudio.google.com/apikey) — **must be "new project"** | Free, no card, ~500 img/day |
| `pollinations` | Stills *and* video (`wan`, `seedance-pro`, `veo`) | [enter.pollinations.ai/keys](https://enter.pollinations.ai/keys) | ~0.039 pollen (≈$0.04) per image; balance starts at 0 |
| `comfy` | Stills *and* video on your own GPU | — | GPU rental (see DEPLOYMENT.md) |

### Running everything on your own pod

No keys, no daily cap, no per-image fee — the pod costs the same whether it
renders one preview or a thousand:

```bash
COMFY_URL=https://<pod>-8188.proxy.runpod.net
PREVIEW_PROVIDER=comfy
VIDEO_PROVIDER=comfy
```

Stills and video are separate graphs, because they need different weights and
have very different runtimes:

```bash
COMFY_IMAGE_WORKFLOW=zimage_probe.json   # ~8s   — needs only Z-Image
COMFY_WORKFLOW=wan22_animate.json        # ~mins — needs Wan weights
```

**Read this before trusting the preview output.** `zimage_probe.json` is plain
img2img on a base model with no identity conditioning, so there is a hard
trade-off with no good setting in between — measured on a 4090, same seed, same
prompt, only `denoise` changed:

| `denoise` | Result |
|---|---|
| 0.65 | The face survives, but the scenario barely applies |
| 0.85 | The scenario is perfect, and it is **someone else's face** |

That is not a tuning problem: img2img re-noises pixels, so prompt freedom and
identity are the same dial. Previews that keep the user's face need a model
that conditions on identity — Qwen-Image-Edit (this pod already has the
`TextEncodeQwenImageEdit` node, it just needs the weights) or a face-swap pass
after generation. Until then treat `zimage_probe.json` as proof the plumbing
works, not as shippable output.

### Turning on real AI

Copy `.env.example` to `.env`, paste your key, restart. That is the whole
change — `.env` is gitignored, and real environment variables still win, so
container and CI config is never overridden by a stale local file.

```bash
cp .env.example .env
# put your key on the GEMINI_API_KEY= line
python -m devstack.run          # now prints "previews  REAL Gemini (free tier)"
```

Check your keys against the live APIs:

```bash
python scripts/check_providers.py           # stills only
python scripts/check_providers.py --video   # also renders a clip (spends credit)
```

It writes what came back to `data/providers/` so you can judge the quality.

### What is genuinely free, measured not quoted

- **Stills: yes, but only on the right kind of key.** Gemini 2.5 Flash Image
  does image editing with a reference photo — "keep this face, change everything
  else" — and the free tier is ~500 images/day with no card. **The catch:** the
  key must come from an *AI-Studio-managed* project. Use "Create API key in new
  project" at <https://aistudio.google.com/apikey>. A key bound to an existing
  Google Cloud project reports `free_tier_requests, limit: 0` on every image
  model and 429s forever — that is not a daily allowance you used up, it is no
  allowance at all, and waiting never clears it. `GeminiImageProvider` detects
  this case specifically and says so.
  At ~500/day, 40 previews per user is roughly 12 new users a day: fine for
  building, not for launch.
- **Video: no.** There is no free image-to-video API. Anonymous Pollinations is
  capped at about **one generation per hour per IP** (verified against the live
  API — the first call works and the rest 401), every video model requires a
  key, and Hugging Face's free tier is $0.10/month of credit. Video is either
  metered credit or your own GPU.

That asymmetry is the whole product argument: free previews sell the paid render.

## The one design decision worth knowing

`workflow.py` binds by **node title**, not node id. You build the graph in
ComfyUI, retitle five nodes (`FY_INPUT_IMAGE`, `FY_POSITIVE`, `FY_OUTPUT`, and
optionally `FY_NEGATIVE`, `FY_SAMPLER`, `FY_LATENT`), export as API format, and
drop the JSON in `workflows/`.

No Python changes when the workflow changes — which matters, because Wan graphs
get re-tuned constantly and hard-coded node ids break on every re-export.
`GET /v1/health` reports exactly which titles are missing.

To check a real GPU box before wiring the app to it:

```bash
python scripts/probe_comfy.py --url https://<pod>-8188.proxy.runpod.net
```

It uploads a photo, binds the graph by title, queues it, follows the websocket,
and downloads the result — every part that only fails against real ComfyUI. It
defaults to `zimage_probe.json`, which needs only the models the stock Z-Image
template downloads, so you can validate the plumbing before any Wan or
face-swap weights exist. Pass `--workflow` once they do.
