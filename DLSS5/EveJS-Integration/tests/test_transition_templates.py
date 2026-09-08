"""Authored-template control flow only; never imports or runs a client module."""
from __future__ import annotations

import ast
import re
import textwrap
from pathlib import Path
from types import SimpleNamespace

import pytest


TEMPLATES = Path(__file__).resolve().parents[1] / "client-patches/templates"
NATIVE_HELPERS = {
    "getDLSS5NativeBridge", "readDLSS5NativeSnapshot",
    "waitForDLSS5ToggleAcknowledgement", "toggleDLSS5NeuralRenderingAndReadState",
}


@pytest.mark.parametrize("ack_sleep,expected", [(1, "OFF"), (50, "OFF"), (None, None)])
def test_native_ack_wait_observes_last_sleep_without_extending_bound(ack_sleep, expected):
    runtime = Runtime()
    before = dict(runtime.snapshot)
    def acknowledge(ms):
        if len(runtime.sleeps) == ack_sleep:
            runtime.toggle()
    runtime.on_sleep = acknowledge
    tree = ast.parse(textwrap.dedent((TEMPLATES / "native_nr_bridge.py.in").read_text()))
    helper = next(node for node in tree.body if isinstance(node, ast.FunctionDef)
                  and node.name == "waitForDLSS5ToggleAcknowledgement")
    module = ast.Module(body=[helper], type_ignores=[])
    env = runtime.environment()
    exec(compile(module, "native-ack-helper", "exec"), env)
    assert env[helper.name](before, 2500) == expected
    assert len(runtime.sleeps) <= 50


class Graphics:
    GFX_UPSCALING_TECHNIQUE = "tech"
    GFX_UPSCALING_SETTING = "preset"
    GFX_FRAMEGENERATION_ENABLED = "fg"
    GFX_SHADER_QUALITY = "shader"
    GFX_TEXTURE_QUALITY = "texture"
    GFX_UPSCALING_TECHNIQUE_DLSS = "DLSS"

    def __init__(self):
        self.current = dict(tech="DLSS", preset=0, fg=0, shader=1, texture=1)
        self.pending = dict(preset=1)
        self.commits = 0

    def Get(self, key):
        return self.current[key]

    def GetPendingOrCurrent(self, key):
        return self.pending.get(key, self.current[key])

    def commit(self):
        changes = dict(self.pending)
        self.current.update(changes)
        self.pending.clear()
        self.commits += 1
        return changes


class Runtime:
    def __init__(self):
        self.graphics = Graphics()
        self.snapshot = dict(state=2, stateSequence=1, toggleSequence=0,
                             lastToggleState=2, addonEpoch=1)
        self.sleeps = []
        self.on_sleep = lambda ms: None
        self.automatic_toggles = 0
        self.ready = True
        self.tech = "DLSS"
        self.scheduled = []
        self.errors = []

    def toggle(self, attempt=0):
        if attempt:
            self.automatic_toggles += 1
        self.snapshot["state"] = 1 if self.snapshot["state"] == 2 else 2
        self.snapshot["stateSequence"] += 1
        self.snapshot["toggleSequence"] += 1
        self.snapshot["lastToggleState"] = self.snapshot["state"]
        return "ON" if self.snapshot["state"] == 2 else "OFF"

    def sleep(self, ms):
        self.sleeps.append(ms)
        self.on_sleep(ms)

    def environment(self):
        return dict(
            gfxsettings=self.graphics,
            logger=SimpleNamespace(info=lambda *a: None, warning=lambda *a: None,
                                   error=lambda *a: self.errors.append(a),
                                   exception=lambda *a: self.errors.append(a)),
            blue=SimpleNamespace(synchro=SimpleNamespace(SleepWallclock=self.sleep)),
            readDLSS5NativeSnapshot=lambda: dict(self.snapshot),
            toggleDLSS5NeuralRenderingAndReadState=self.toggle,
            trinity=SimpleNamespace(device=SimpleNamespace(
                DoesD3DDeviceExist=lambda: self.ready,
                GetUpscalingInfo=lambda: {"technique": self.tech})),
            uthread=SimpleNamespace(new=self.scheduled.append),
        )

    def load(self, filename, slots):
        source = (TEMPLATES / filename).read_text(encoding="utf-8")
        fragment = (TEMPLATES / "native_nr_bridge.py.in").read_text(encoding="utf-8")
        source = source.replace("        @SHARED:native_nr_bridge@", fragment.rstrip("\n"))
        source = re.sub(r"@LOCAL:([a-z_]+)@", lambda m: slots[m[1]], source)
        tree = ast.parse(source)
        method = tree.body[0].body[0]
        method.body = [node for node in method.body if not (
            isinstance(node, ast.FunctionDef) and node.name in NATIVE_HELPERS)]
        env = self.environment()
        exec(compile(tree, str(TEMPLATES / filename), "exec"), env)
        return env[tree.body[0].name]()

    def menu(self):
        menu = self.load("systemmenu_apply_graphics.py.in", {
            "graphics_setup": "pass", "current_query": "self.tech",
            "target_getter": "gfxsettings.Get('tech')",
            "preset_getter": "gfxsettings.Get('preset')",
            "framegen_getter": "gfxsettings.Get('fg')",
            "graphics_commit": "changes = gfxsettings.commit()",
            "upscaling_condition": "self.tech != targetUpscalingTechnique or self.preset != gfxsettings.Get('preset')",
            "upscaling_call": "self.tech = targetUpscalingTechnique; self.preset = gfxsettings.Get('preset')",
            "ready_condition": "self.not_ready", "panel_refresh": "pass",
            "graphics_event": "pass", "crash_key": "pass", "window_guard": "pass",
        })
        menu.tech, menu.preset, menu.not_ready = "DLSS", 0, False
        return menu

    def device(self):
        return self.load("device_create.py.in", {"startup_body": "pass"})


@pytest.mark.parametrize("new_change", [False, True])
def test_failed_apply_keeps_desired_on_until_a_ready_retry(new_change):
    runtime = Runtime()
    menu = runtime.menu()
    menu.not_ready = True
    menu.ApplyGraphicsSettings()
    assert runtime.snapshot["state"] == 1
    assert runtime.graphics._dlss5NRWantedV13 == "ON"
    assert runtime.graphics._dlss5NRTransitionV13["needsRearm"]
    menu.not_ready = False
    if new_change:
        runtime.graphics.pending = dict(preset=2)
    menu.ApplyGraphicsSettings()
    assert runtime.snapshot["state"] == 2
    assert runtime.graphics._dlss5NRWantedV13 == "ON"
    assert not runtime.graphics._dlss5NRTransitionV13["needsRearm"]


def test_retry_cannot_rearm_an_unready_renderer_without_new_pending_values():
    runtime = Runtime()
    menu = runtime.menu()
    menu.not_ready = True
    menu.ApplyGraphicsSettings()
    menu.ApplyGraphicsSettings()
    assert runtime.snapshot["state"] == 1
    assert runtime.automatic_toggles == 1
    assert runtime.graphics._dlss5NRWantedV13 == "ON"


@pytest.mark.parametrize("interruption", ["two_manual_toggles", "epoch", "unknown", "state_sequence"])
def test_settling_requires_continuous_known_off_and_same_lifetime(interruption):
    runtime = Runtime()
    menu = runtime.menu()

    def interrupt(ms):
        if ms != 5000:
            return
        if interruption == "two_manual_toggles":
            runtime.toggle()
            runtime.toggle()
        elif interruption == "epoch":
            runtime.snapshot["addonEpoch"] += 1
        elif interruption == "unknown":
            runtime.snapshot["state"] = 0
        else:
            runtime.snapshot["stateSequence"] += 1

    runtime.on_sleep = interrupt
    menu.ApplyGraphicsSettings()
    assert runtime.graphics.commits == 0
    assert runtime.automatic_toggles == 1
    assert runtime.graphics._dlss5NRTransitionV13["needsRearm"]
    if interruption == "two_manual_toggles":
        assert runtime.graphics._dlss5NRWantedV13 == "OFF"
        runtime.on_sleep = lambda ms: None
        menu.ApplyGraphicsSettings()
        assert runtime.snapshot["state"] == 1
        assert runtime.automatic_toggles == 1


@pytest.mark.parametrize("when", ["between_attempts", "rearm_delay", "readiness_delay"])
def test_latest_manual_off_is_preserved(when):
    runtime = Runtime()
    menu = runtime.menu()
    if when == "between_attempts":
        menu.not_ready = True
        menu.ApplyGraphicsSettings()
        runtime.toggle()
        runtime.toggle()
        menu.not_ready = False
    else:
        trigger = 3000 if when == "rearm_delay" else 25
        menu.not_ready = when == "readiness_delay"

        def manual_choice(ms):
            if ms == trigger:
                runtime.toggle()
                runtime.toggle()
                menu.not_ready = False
                runtime.on_sleep = lambda ms: None

        runtime.on_sleep = manual_choice
    menu.ApplyGraphicsSettings()
    assert runtime.snapshot["state"] == 1
    assert runtime.graphics._dlss5NRWantedV13 == "OFF"
    assert runtime.automatic_toggles == 1


def test_startup_timeout_retries_on_later_device_creation_then_stops_on_success():
    runtime = Runtime()
    device = runtime.device()
    runtime.ready = False
    device.CreateDevice()
    runtime.scheduled.pop(0)()
    assert runtime.graphics._dlss5StartupResult == "readiness-timeout"
    runtime.ready = True
    device.CreateDevice()
    runtime.scheduled.pop(0)()
    assert runtime.graphics._dlss5StartupResult == "preserved-dlss"
    assert runtime.graphics._dlss5StartupAttempts == 2
    device.CreateDevice()
    assert not runtime.scheduled
    assert runtime.automatic_toggles == 0


def test_startup_failure_attempts_are_bounded_and_concurrent_workers_excluded():
    runtime = Runtime()
    device = runtime.device()
    runtime.ready = False
    for attempt in range(3):
        device.CreateDevice()
        device.CreateDevice()
        assert len(runtime.scheduled) == 1
        runtime.scheduled.pop(0)()
    device.CreateDevice()
    assert not runtime.scheduled
    assert runtime.graphics._dlss5StartupAttempts == 3
    assert runtime.automatic_toggles == 0


def test_non_dlss_startup_confirms_off_once():
    runtime = Runtime()
    runtime.tech = "FSR"
    device = runtime.device()
    device.CreateDevice()
    runtime.scheduled.pop(0)()
    assert runtime.graphics._dlss5StartupResult == "confirmed-off"
    assert runtime.snapshot["state"] == 1
    assert runtime.automatic_toggles == 1


def test_rearm_epoch_change_does_not_toggle_uncertain_state():
    runtime = Runtime()
    menu = runtime.menu()
    runtime.on_sleep = lambda ms: runtime.snapshot.update(addonEpoch=2) if ms == 3000 else None
    menu.ApplyGraphicsSettings()
    assert runtime.snapshot["state"] == 1
    assert runtime.automatic_toggles == 1
    assert runtime.graphics._dlss5NRTransitionV13["needsRearm"]
