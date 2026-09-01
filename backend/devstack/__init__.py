"""Local stand-ins for the two services that need money or a GPU.

`fake_gemini` and `fake_comfy` speak the real wire protocols, so the production
code in `app/` runs against them unmodified. Swapping to the real thing is two
environment variables and no code change.
"""
