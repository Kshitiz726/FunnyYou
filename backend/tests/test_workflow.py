"""Tests for the workflow binder — the part that must never silently misfire."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from app import workflow as wf

WORKFLOW_DIR = Path(__file__).parent.parent / "workflows"


@pytest.fixture
def graph() -> dict:
    return wf.load(WORKFLOW_DIR / "wan22_animate.json")


def test_shipped_workflow_has_every_required_marker(graph: dict) -> None:
    assert wf.validate(graph) == []


def test_build_binds_image_and_prompt(graph: dict) -> None:
    built = wf.build(
        graph,
        wf.RenderParams(image_name="abc.jpg", prompt="the person as a chef"),
    )

    image_node = wf.find_by_title(built, wf.MARKER_IMAGE)
    assert built[image_node]["inputs"]["image"] == "abc.jpg"

    positive = wf.find_by_title(built, wf.MARKER_POSITIVE)
    assert built[positive]["inputs"]["text"] == "the person as a chef"

    negative = wf.find_by_title(built, wf.MARKER_NEGATIVE)
    assert built[negative]["inputs"]["text"] == wf.DEFAULT_NEGATIVE


def test_build_sets_size_and_frame_count_when_they_are_widgets() -> None:
    synthetic = {
        "1": {"class_type": "LoadImage", "inputs": {"image": "x.png"},
              "_meta": {"title": wf.MARKER_IMAGE}},
        "2": {"class_type": "CLIPTextEncode", "inputs": {"text": ""},
              "_meta": {"title": wf.MARKER_POSITIVE}},
        "3": {"class_type": "EmptyLatentImage",
              "inputs": {"width": 512, "height": 512, "length": 1},
              "_meta": {"title": wf.MARKER_LATENT}},
        "4": {"class_type": "SaveVideo", "inputs": {},
              "_meta": {"title": wf.MARKER_OUTPUT}},
    }
    built = wf.build(synthetic, wf.RenderParams(
        image_name="a.jpg", prompt="x", width=640, height=640, frames=49))
    latent = built["3"]["inputs"]
    assert (latent["width"], latent["height"], latent["length"]) == (640, 640, 49)


def test_wired_geometry_is_never_overwritten(graph: dict) -> None:
    """The shipped character-swap graph drives size from the template clip.

    Its width/height/length are wired to the author's PrimitiveInt nodes rather
    than being widgets, because the output has to match the template video the
    performer is being replaced in. Writing a literal over a `[node, slot]`
    reference would silently detach those nodes and change the render, so the
    binder must leave wired inputs exactly as authored.
    """
    latent_id = wf.find_by_title(graph, wf.MARKER_LATENT)
    before = graph[latent_id]["inputs"]
    if not isinstance(before.get("width"), list):
        pytest.skip("this graph's latent size is a widget, not a link")

    built = wf.build(graph, wf.RenderParams(
        image_name="a.jpg", prompt="x", width=640, height=640, frames=49))
    after = built[latent_id]["inputs"]
    for key in ("width", "height", "length"):
        assert after[key] == before[key], f"{key} was overwritten"


def test_build_does_not_mutate_the_source_graph(graph: dict) -> None:
    before = json.dumps(graph, sort_keys=True)
    wf.build(graph, wf.RenderParams(image_name="a.jpg", prompt="hello"))
    assert json.dumps(graph, sort_keys=True) == before


def test_seed_is_randomised_but_deterministic_when_given(graph: dict) -> None:
    sampler = wf.MARKER_SAMPLER

    fixed = wf.build(graph, wf.RenderParams(image_name="a.jpg", prompt="x", seed=42))
    assert fixed[wf.find_by_title(fixed, sampler)]["inputs"]["seed"] == 42

    seeds = {
        wf.build(graph, wf.RenderParams(image_name="a.jpg", prompt="x"))[
            wf.find_by_title(graph, sampler)
        ]["inputs"]["seed"]
        for _ in range(8)
    }
    assert len(seeds) > 1, "unseeded renders must vary"


def test_build_never_overwrites_a_wired_connection() -> None:
    # A wired input is [node_id, slot]. Clobbering it would silently detach the
    # graph and produce a black video.
    graph = {
        "1": {
            "class_type": "LoadImage",
            "_meta": {"title": wf.MARKER_IMAGE},
            "inputs": {"image": ["99", 0]},
        },
        "2": {
            "class_type": "CLIPTextEncode",
            "_meta": {"title": wf.MARKER_POSITIVE},
            "inputs": {"text": ""},
        },
        "3": {
            "class_type": "SaveVideo",
            "_meta": {"title": wf.MARKER_OUTPUT},
            "inputs": {},
        },
    }
    built = wf.build(graph, wf.RenderParams(image_name="new.jpg", prompt="x"))
    assert built["1"]["inputs"]["image"] == ["99", 0]


def test_missing_marker_names_the_problem() -> None:
    graph = {
        "1": {
            "class_type": "LoadImage",
            "_meta": {"title": wf.MARKER_IMAGE},
            "inputs": {},
        }
    }
    # FY_POSITIVE is not required: a pure face-swap graph carries no text
    # conditioning at all, so demanding a prompt node would reject a
    # perfectly good workflow.
    assert set(wf.validate(graph)) == {wf.MARKER_OUTPUT}

    with pytest.raises(wf.WorkflowError) as excinfo:
        wf.build(graph, wf.RenderParams(image_name="a.jpg", prompt="x"))
    assert wf.MARKER_OUTPUT in str(excinfo.value)


def test_ui_format_export_is_rejected_with_a_useful_message(tmp_path: Path) -> None:
    ui_export = tmp_path / "ui.json"
    ui_export.write_text(json.dumps({"nodes": [{"id": 1}], "links": []}))

    with pytest.raises(wf.WorkflowError, match="Export \\(API\\)"):
        wf.load(ui_export)


def test_missing_file_is_reported_clearly(tmp_path: Path) -> None:
    with pytest.raises(wf.WorkflowError, match="not found"):
        wf.load(tmp_path / "nope.json")


def test_template_video_binds_for_character_swap() -> None:
    """Character swap needs two inputs: the customer's face and the template clip.

    The clip is chosen per scenario by the caller, so it has to be bindable at
    render time rather than authored into the graph.
    """
    graph = {
        "1": {"class_type": "LoadImage", "inputs": {"image": "x.png"},
              "_meta": {"title": wf.MARKER_IMAGE}},
        "2": {"class_type": "CLIPTextEncode", "inputs": {"text": ""},
              "_meta": {"title": wf.MARKER_POSITIVE}},
        "3": {"class_type": "VHS_LoadVideo", "inputs": {"video": "authored.mp4"},
              "_meta": {"title": wf.MARKER_TEMPLATE_VIDEO}},
        "4": {"class_type": "SaveVideo", "inputs": {},
              "_meta": {"title": wf.MARKER_OUTPUT}},
    }

    bound = wf.build(graph, wf.RenderParams(
        image_name="face.jpg", prompt="p", template_video="superhero.mp4"))
    assert bound["3"]["inputs"]["video"] == "superhero.mp4"

    # Omitting it must leave the authored clip alone rather than blanking it.
    untouched = wf.build(graph, wf.RenderParams(image_name="face.jpg", prompt="p"))
    assert untouched["3"]["inputs"]["video"] == "authored.mp4"


def test_the_clients_real_workflow_binds() -> None:
    """Guards the converted Wan Animate graph, not a hand-made fixture.

    This file is produced by scripts/workflow_convert.py + prepare_wan_workflow.py
    from what the client sends. If a re-conversion drops a marker or renumbers a
    node, the app would fail at render time on a paying user; this fails in CI.
    """
    path = Path(__file__).parent.parent / "workflows" / "wan22_animate.json"
    if not path.is_file():
        pytest.skip("wan22_animate.json not present")

    graph = wf.load(path)
    assert wf.validate(graph) == []

    bound = wf.build(graph, wf.RenderParams(
        image_name="customer.jpg", prompt="riding a dragon",
        template_video="dragon.mp4", width=832, height=480, frames=77))

    image_node = wf.find_by_title(bound, wf.MARKER_IMAGE)
    assert bound[image_node]["inputs"]["image"] == "customer.jpg"

    video_node = wf.find_by_title(bound, wf.MARKER_TEMPLATE_VIDEO)
    assert bound[video_node]["inputs"]["video"] == "dragon.mp4"

    positive = wf.find_by_title(bound, wf.MARKER_POSITIVE)
    assert bound[positive]["inputs"]["text"] == "riding a dragon"

    # Every wired input must point at a node that exists, or ComfyUI rejects it.
    for node_id, node in bound.items():
        for key, value in node["inputs"].items():
            if isinstance(value, list) and len(value) == 2:
                assert str(value[0]) in bound, f"{node_id}.{key} -> missing {value[0]}"
