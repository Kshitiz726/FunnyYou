"""The box holds one job at a time, and comes back when it dies.

These are the two properties that stop the 62 GB container being OOM-killed
and, when something kills it anyway, stop a customer being left with a job
that never finishes. Both are invisible when they work, which is exactly why
they need tests.
"""

from __future__ import annotations

import asyncio

import pytest

from app.gpu_guard import ComfySupervisor, gpu_turn

pytestmark = pytest.mark.asyncio


class Box:
    """A ComfyUI stand-in that records the order things happened in."""

    def __init__(self, *, healthy: bool = True) -> None:
        self.events: list[str] = []
        self.healthy = healthy
        self.frees = 0

    async def free_models(self) -> None:
        self.frees += 1
        self.events.append("free")

    async def health(self) -> bool:
        return self.healthy


async def test_two_jobs_never_hold_the_box_at_once() -> None:
    """The hole the earlier fixes left open.

    Freeing models is an out-of-band call that takes effect immediately, so a
    preview arriving mid-render would unload the render's weights or stack its
    own on top. Interleaved events here would mean that can still happen.
    """
    box = Box()

    async def job(name: str) -> None:
        async with gpu_turn(box, name):
            box.events.append(f"start {name}")
            await asyncio.sleep(0.02)
            box.events.append(f"end {name}")

    await asyncio.gather(job("a"), job("b"))

    starts = [e for e in box.events if e.startswith(("start", "end"))]
    # Whichever won, it finished before the other began.
    assert starts in (
        ["start a", "end a", "start b", "end b"],
        ["start b", "end b", "start a", "end a"],
    ), box.events


async def test_the_box_is_emptied_inside_the_turn_not_before_it() -> None:
    """Freeing outside the lock is a race, not a fix.

    The free has to land after the previous job has let go and before this one
    queues anything, or it unloads weights somebody else is mid-sample on.
    """
    box = Box()

    async def job(name: str) -> None:
        async with gpu_turn(box, name):
            box.events.append(f"work {name}")
            await asyncio.sleep(0.01)

    await asyncio.gather(job("a"), job("b"))

    assert box.frees == 2
    # Every free is immediately followed by the work it made room for.
    for i, event in enumerate(box.events):
        if event == "free":
            assert box.events[i + 1].startswith("work"), box.events


async def test_the_turn_is_released_even_when_the_job_explodes() -> None:
    """A failed render must not wedge the box for everyone after it."""
    box = Box()

    with pytest.raises(RuntimeError):
        async with gpu_turn(box, "doomed"):
            raise RuntimeError("render died")

    async with gpu_turn(box, "next"):
        pass  # Reaching here at all is the assertion.


async def test_a_healthy_box_is_not_restarted() -> None:
    """Recovery is for a dead server, not for a render that simply failed."""
    box = Box(healthy=True)
    supervisor = ComfySupervisor("this-command-does-not-exist")

    assert await supervisor.recover(box) is False


async def test_a_dead_box_is_restarted_and_reported_back() -> None:
    box = Box(healthy=False)
    ran: list[bool] = []

    # Stand in for the restart script: flip the box back to healthy.
    class Revivable(ComfySupervisor):
        async def ensure_up(self, client):
            ran.append(True)
            client.healthy = True
            return True

    supervisor = Revivable("restart-comfy")
    assert await supervisor.recover(box) is True
    assert ran, "the box was dead and nothing tried to restart it"


async def test_without_a_restart_command_recovery_gives_up_quietly() -> None:
    """On a laptop there is nothing to restart, and that must not raise."""
    box = Box(healthy=False)
    supervisor = ComfySupervisor("")

    assert supervisor.enabled is False
    assert await supervisor.recover(box) is False


async def test_a_box_whose_health_check_throws_counts_as_down() -> None:
    """A server killed mid-prompt drops the connection rather than answering."""

    class Broken(Box):
        async def health(self) -> bool:
            raise OSError("connection reset")

    supervisor = ComfySupervisor("")
    assert await supervisor.recover(Broken()) is False
