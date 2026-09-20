"""One job on the render box at a time, and a way back after a crash.

The box is a 62 GB container. Nothing here is about making renders faster; it
is about the one failure that cannot be recovered from gracefully, which is the
kernel killing ComfyUI because two things wanted its memory at once.

The history is worth keeping, because each fix looked complete on its own:

1. The render was split into two queued prompts so Wan's weights and the face
   restore's would not be resident together. Splitting was not enough --
   ComfyUI keeps a finished prompt's models loaded, so pass two stacked on pass
   one and the box died anyway.
2. So pass two started by asking ComfyUI to drop everything. That fixed the
   boundary *inside* a render, and missed what the box was already holding when
   the render arrived: the preview face swaps the app fires the moment the
   selfie is taken.
3. So every pass starts by dropping everything. Which leaves the last hole --
   two jobs overlapping. Freeing is global and immediate, so a preview arriving
   mid-render would either unload a running render's weights or, worse, load
   its own on top.

This module closes that last hole by refusing to let two jobs run at once, and
then accepts that something can still go wrong and brings ComfyUI back up when
it does.
"""

from __future__ import annotations

import asyncio
import contextlib
import logging
import shlex
import time
import weakref

log = logging.getLogger(__name__)

# Every queued prompt, from any provider, takes this turn. Module-level rather
# than per-instance on purpose: previews and renders are separate provider
# objects pointed at the same single GPU.
#
# Keyed by event loop, because an asyncio lock belongs to the loop it was first
# awaited on and raises if it is reused from another. The server has exactly
# one loop, so in production this holds exactly one lock and the key never
# matters; it matters when a loop is replaced, which would otherwise leave a
# lock that refuses every acquire. Weak keys so a finished loop does not pin
# itself in memory.
_turns: weakref.WeakKeyDictionary = weakref.WeakKeyDictionary()


def _lock() -> asyncio.Lock:
    loop = asyncio.get_running_loop()
    lock = _turns.get(loop)
    if lock is None:
        lock = asyncio.Lock()
        _turns[loop] = lock
    return lock


@contextlib.asynccontextmanager
async def gpu_turn(client, what: str = "job"):
    """Hold the box for one queued prompt, starting from an empty one.

    Freeing happens *inside* the lock. Outside it the call races: `/free` is an
    out-of-band HTTP call, not a queued node, so it takes effect immediately --
    including in the middle of somebody else's render.

    The turn covers queueing *and* waiting for the result, because ComfyUI
    holds a prompt's weights for as long as it is running it. Releasing at
    submission would let the next job load its own on top, which is the whole
    problem.
    """
    lock = _lock()
    if lock.locked():
        log.info("Waiting for the render box: %s is queued behind another job", what)

    started = time.monotonic()
    async with lock:
        waited = time.monotonic() - started
        if waited > 1.0:
            log.info("Render box free after %.0fs, starting %s", waited, what)
        await client.free_models()
        try:
            yield
        finally:
            log.debug("Render box released after %s", what)


class ComfySupervisor:
    """Brings ComfyUI back when it is not answering.

    A render that dies because the server vanished is the one failure the user
    cannot do anything about, and the one most likely to happen while nobody is
    watching. Given a restart command this puts the server back and lets the
    caller try again; given none it does nothing and says so once, which is the
    right behaviour on a developer's laptop.
    """

    def __init__(
        self,
        restart_command: str = "",
        *,
        wait_s: float = 180.0,
        poll_s: float = 3.0,
    ) -> None:
        self._command = restart_command.strip()
        self._wait_s = wait_s
        self._poll_s = poll_s
        self._lock = asyncio.Lock()
        self._warned = False

    @property
    def enabled(self) -> bool:
        return bool(self._command)

    async def recover(self, client) -> bool:
        """True only when the box had died and is now back up.

        The distinction matters to the caller: a render that failed while
        ComfyUI kept answering failed on its own merits, and running it again
        will fail the same way.
        """
        if await _healthy(client):
            return False
        return await self.ensure_up(client)

    async def ensure_up(self, client) -> bool:
        """True if ComfyUI is answering, restarting it first if it is not.

        Serialised: several renders failing at once must not each start their
        own copy of the server.
        """
        if await _healthy(client):
            return True

        if not self.enabled:
            if not self._warned:
                self._warned = True
                log.warning(
                    "ComfyUI is not answering and COMFY_RESTART_CMD is unset, "
                    "so it cannot be restarted automatically"
                )
            return False

        async with self._lock:
            # Someone else may have fixed it while we waited for the lock.
            if await _healthy(client):
                return True

            log.warning("ComfyUI is not answering — restarting it")
            try:
                process = await asyncio.create_subprocess_exec(
                    *shlex.split(self._command),
                    stdout=asyncio.subprocess.DEVNULL,
                    stderr=asyncio.subprocess.DEVNULL,
                )
                await process.wait()
            except (OSError, ValueError) as exc:
                log.error("Could not run the ComfyUI restart command: %r", exc)
                return False

            return await self._wait_for_health(client)

    async def _wait_for_health(self, client) -> bool:
        loop = asyncio.get_running_loop()
        deadline = loop.time() + self._wait_s
        while loop.time() < deadline:
            if await _healthy(client):
                log.info("ComfyUI is back up")
                return True
            await asyncio.sleep(self._poll_s)
        log.error("ComfyUI did not come back within %.0fs", self._wait_s)
        return False


async def _healthy(client) -> bool:
    try:
        return bool(await client.health())
    except Exception as exc:  # noqa: BLE001 - health must never raise
        log.debug("ComfyUI health check raised: %r", exc)
        return False
