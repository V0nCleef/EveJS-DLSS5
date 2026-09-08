"""Public adapter preparation against disposable profile/client directories."""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import uuid

import pytest


PACKAGE = Path(__file__).resolve().parents[2]
LAUNCHER_SOURCE = Path(os.environ.get("EVEJS_LAUNCHER_SOURCE", str(PACKAGE.parents[2] / "source")))
sys.path.insert(0, str(LAUNCHER_SOURCE))
from src.core.mod_api_manifest import read_api_manifest
from src.core.mod_api_runtime import validate_helper_result
from src.core.mod_settings import ModSettingsContext, profile_identity
from src.core.mod_settings_schema import parse_settings_schema


@pytest.fixture
def profile(tmp_path):
    root = tmp_path / "EveJS"
    mod = root / "mods" / "DLSS5"
    integration = mod / "EveJS-Integration"
    integration.mkdir(parents=True)
    shutil.copy2(PACKAGE / "evejs-launcher.mod.json", mod)
    shutil.copy2(PACKAGE / "EveJS-Integration/Invoke-LauncherMod.ps1", integration)
    shutil.copy2(PACKAGE / "EveJS-Integration/ReShade-Lists.ps1", integration)
    client = tmp_path / "physical" / "tq"
    (client / "bin64").mkdir(parents=True)
    journal = client.parent / "_evejs/dlss5/install/active-install.json"
    journal.parent.mkdir(parents=True)
    journal.write_text(json.dumps(dict(schemaVersion=5, stateScope="client", clientRoot=str(client), status="installed", evejsRoot=str(root))))
    profile_root = tmp_path / "profiles" / "profile-a"
    settings_root = tmp_path / "settings" / "profile-a"
    profile_root.mkdir(parents=True)
    settings_root.mkdir(parents=True)
    context = ModSettingsContext(root, mod, client, profile_identity(profile_root), profile_root, settings_root)
    descriptor = read_api_manifest(root, mod)
    request = {
        "protocol": "evejs_launcher_mod_v1", "requestId": str(uuid.uuid4()), "action": "prepare_profile",
        "mod": {"id": descriptor.id, "version": descriptor.version, "identity": descriptor.identity, "root": str(root), "path": str(mod)},
        "runtime": {"backend": "native", "evejsRoot": str(root), "clientRoot": str(client)},
        "profile": {"id": context.profile_id, "root": str(profile_root), "settingsRoot": str(settings_root), "modDataRoot": str(context.mod_data_root)},
        "settings": {"global": {}, "profile": {"neural_rendering": True}},
    }
    return context, descriptor, request


def invoke(tmp_path, profile):
    context, descriptor, request = profile
    request_path, result_path = tmp_path / "request.json", tmp_path / "result.json"
    request_path.write_text(json.dumps(request), encoding="utf-8")
    completed = subprocess.run([
        "powershell.exe", "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
        "-File", str(descriptor.launcher_api.helper.path), "-RequestPath", str(request_path), "-ResultPath", str(result_path),
    ], capture_output=True, text=True, timeout=20, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    assert result_path.exists(), completed.stdout + completed.stderr
    result = json.loads(result_path.read_text(encoding="utf-8-sig"))
    validated = validate_helper_result(result, descriptor, context, request["action"], request["requestId"], request_path)
    assert (completed.returncode == 0) is validated.success, (result, completed.stderr)
    return result


def put(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


@pytest.mark.parametrize("origin", ["shared", "legacy", "private"])
def test_profile_preparation_preserves_f6_off_and_other_values_without_shared_writes(tmp_path, profile, origin):
    context, descriptor, request = profile
    paths = {
        "shared": context.client_root / "bin64/ReShade.ini",
        "legacy": context.profile_root / "DLSS5/ReShade.ini",
        "private": context.mod_data_root / "ReShade.ini",
    }
    put(paths[origin], "[RenoDX.DLSS5]\nNeuralUplift=0\nCustom=7\n[OtherMod]\nKeep=value\n")
    before = {path: path.read_bytes() for path in context.client_root.parent.rglob("*") if path.is_file()}
    result = invoke(tmp_path, profile)
    assert result["success"], result
    values = {tuple(row["key"]): row["value"] for row in result["contributions"]}
    assert values[("RenoDX.DLSS5", "NeuralUplift")] == "0"
    assert values[("OtherMod", "Keep")] == "value"
    assert values[("RenoDX.DLSS5", "Custom")] == "7"
    assert values[("ADDON", "AddonPath")] == str(context.client_root / "bin64")
    assert result["environment"] == {"TRINITYPLATFORM": "dx12", "RESHADE_BASE_PATH_OVERRIDE": str(context.mod_data_root)}
    assert all(row["base"] == "profile" for row in result["contributions"])
    after = {path: path.read_bytes() for path in context.client_root.parent.rglob("*") if path.is_file()}
    assert before == after
    if origin != "private":
        assert not paths["private"].exists()  # Host applies the proposal separately.


def test_existing_private_values_take_precedence_over_legacy_profile(tmp_path, profile):
    context, _, _ = profile
    put(context.profile_root / "DLSS5/ReShade.ini", "[RenoDX.DLSS5]\nNeuralUplift=0\nCustom=preserve\n")
    put(context.mod_data_root / "ReShade.ini", "[RenoDX.DLSS5]\nNeuralUplift=1\n")
    result = invoke(tmp_path, profile)
    assert result["success"]
    assert next(row["value"] for row in result["contributions"] if row["key"] == ["RenoDX.DLSS5", "NeuralUplift"]) == "1"
    assert next(row["value"] for row in result["contributions"] if row["key"] == ["RenoDX.DLSS5", "Custom"]) == "preserve"


@pytest.mark.parametrize("origin", ["shared", "legacy", "private"])
@pytest.mark.parametrize("existing,expected", [
    ("other.addon64", "other.addon64,renodx-dlss5.addon64"),
    ("first.addon64,name,,withcomma.addon64", "first.addon64,name,,withcomma.addon64,renodx-dlss5.addon64"),
    ("first.addon64,RENODX-DLSS5.ADDON64,last.addon64", "first.addon64,RENODX-DLSS5.ADDON64,last.addon64"),
    ("renodx-dlss5.addon64", "renodx-dlss5.addon64"),
])
def test_early_addon_list_preserves_neighbors_and_does_not_duplicate_dlss(tmp_path, profile, origin, existing, expected):
    context, _, _ = profile
    source = {"shared": context.client_root / "bin64/ReShade.ini",
              "legacy": context.profile_root / "DLSS5/ReShade.ini",
              "private": context.mod_data_root / "ReShade.ini"}[origin]
    original = "[ADDON]\nLoadFromDllMain=" + existing + "\n"
    put(source, original)
    result = invoke(tmp_path, profile)
    assert result["success"], result
    value = next(row["value"] for row in result["contributions"] if row["key"] == ["ADDON", "LoadFromDllMain"])
    assert value == expected
    assert source.read_text(encoding="utf-8") == original


@pytest.mark.parametrize("origin", ["shared", "legacy"])
def test_asset_paths_preserve_escaped_commas_during_migration(tmp_path, profile, origin):
    context, _, _ = profile
    source = (context.client_root / "bin64" if origin == "shared"
              else context.profile_root / "DLSS5")
    original = ("[GENERAL]\nEffectSearchPaths=.\\Shaders,,Extra,C:\\User,,Shaders\n"
                "TextureSearchPaths=.\\Textures,,Extra,C:\\User,,Textures\n")
    put(source / "ReShade.ini", original)
    result = invoke(tmp_path, profile)
    assert result["success"], result
    values = {tuple(row["key"]): row["value"] for row in result["contributions"]}
    for kind in ("Shaders", "Textures"):
        key = "EffectSearchPaths" if kind == "Shaders" else "TextureSearchPaths"
        expected = str(source).replace(",", ",,") + "\\.\\" + kind + ",,Extra,C:\\User,," + kind
        assert values[("GENERAL", key)] == expected
    assert (source / "ReShade.ini").read_text() == original


def test_legacy_preset_and_relative_asset_locations_survive_private_migration(tmp_path, profile):
    context, _, _ = profile
    legacy = context.profile_root / "DLSS5"
    put(legacy / "ReShade.ini", "[GENERAL]\nPresetPath=.\\MyPreset.ini\nEffectSearchPaths=.\\Shaders,C:\\UserShaders\n[RenoDX.DLSS5]\nNeuralUplift=0\n")
    put(legacy / "MyPreset.ini", "Techniques=MyEffect\n[MyEffect.fx]\nAmount=0.7\n")
    result = invoke(tmp_path, profile)
    assert result["success"], result
    values = {(row["path"], tuple(row["key"])): row["value"] for row in result["contributions"]}
    assert values[("ReShadePreset.ini", ("Techniques",))] == "MyEffect"
    assert values[("ReShadePreset.ini", ("MyEffect.fx", "Amount"))] == "0.7"
    assert values[("ReShade.ini", ("GENERAL", "PresetPath"))] == str(context.mod_data_root / "ReShadePreset.ini")
    assert values[("ReShade.ini", ("GENERAL", "EffectSearchPaths"))] == str(legacy) + "\\.\\Shaders,C:\\UserShaders"
    assert (legacy / "MyPreset.ini").exists()


@pytest.mark.parametrize("bad_ini", [
    "[INSTALL]\nBasePath=C:\\another-profile\n",
    "[RenoDX.DLSS5]\nNeuralUplift=0\nNeuralUplift=1\n",
    "[RenoDX.DLSS5]\nNeuralUplift=unexpected\n",
])
def test_ambiguous_or_redirected_profile_config_is_preserved(tmp_path, profile, bad_ini):
    context, _, _ = profile
    source = context.client_root / "bin64/ReShade.ini"
    put(source, bad_ini)
    result = invoke(tmp_path, profile)
    assert not result["success"] and result["state"] == "failed"
    assert source.read_text(encoding="utf-8") == bad_ini
    assert not (context.mod_data_root / "ReShade.ini").exists()


def test_private_directory_must_belong_to_selected_profile(tmp_path, profile):
    _, _, request = profile
    request["profile"]["modDataRoot"] = str(tmp_path / "other-profile")
    result = invoke(tmp_path, profile)
    assert not result["success"]
    assert "inside the selected profile" in result["message"]


def test_binary_removal_is_global_not_per_profile(tmp_path, profile):
    _, _, request = profile
    request["action"] = "prepare_remove"
    result = invoke(tmp_path, profile)
    assert not result["success"]
    assert "global to the physical client" in result["message"]


def test_maintained_settings_support_every_launcher_language_and_boolean_ini_storage(tmp_path, profile):
    _, descriptor, _ = profile
    schema = parse_settings_schema(descriptor.settings)
    field = schema.fields[0]
    expected = {"en", "zh_CN", "ja", "ko", "fr", "de", "nl", "ru"}
    assert set(field.label) == set(field.description) == set(field.group) == expected
    assert field.storage == "numeric_boolean" and field.scope == "profile"

@pytest.mark.parametrize("terminal,fail_verify", [("installed", False), ("restored", False), ("installed", True), ("restored", True)])
def test_recovery_receipt_reports_retained_version_and_failed_verification(tmp_path, profile, terminal, fail_verify):
    context, descriptor, request = profile
    request["action"] = "recover"
    request["profile"] = None
    journal_path = context.client_root.parent / "_evejs/dlss5/install/active-install.json"
    journal = json.loads(journal_path.read_text())
    journal.update(integrationVersion="0.5.7", status=terminal)
    journal_path.write_text(json.dumps(journal))
    manager = context.mod_folder / "EveJS-Integration/Manage-EveJSDLSS5.ps1"
    # Exercise the real adapter/process/result contract with a controlled binary
    # manager. Actual retained-byte verification is tested in PowerShell below.
    manager.write_text("""param($Action,$Profile,$ClientRoot,$EveJSRootPath,$WorkspaceRoot)
Add-Content -LiteralPath (Join-Path $ClientRoot 'actions.txt') -Value $Action
if ($Action -eq 'Verify' -and %s) { Write-Error 'fixture byte mismatch'; exit 1 }
""" % ("$true" if fail_verify else "$false"))
    result = invoke(tmp_path, profile)
    assert result["success"] is (not fail_verify), result
    receipt = json.loads((context.client_root / result["receipt"]["path"]).read_text())
    assert receipt["adapterVersion"] == read_api_manifest(context.evejs_root, context.mod_folder).version
    assert receipt["packageVersion"] == "0.5.7"
    assert receipt["state"] == ("recoverable" if fail_verify else "active" if terminal == "installed" else "restored")
    assert json.loads(journal_path.read_text())["integrationVersion"] == "0.5.7"
    assert (context.client_root / 'actions.txt').read_text().splitlines() == ["Recover", "Verify"]


def test_two_server_receipts_do_not_overwrite_each_other(tmp_path, profile):
    context, descriptor, request = profile
    request["action"] = "recover"
    request["profile"] = None
    manager = context.mod_folder / "EveJS-Integration/Manage-EveJSDLSS5.ps1"
    manager.write_text("param($Action,$Profile,$ClientRoot,$EveJSRootPath,$WorkspaceRoot)\n")
    first = invoke(tmp_path, profile)
    assert first["success"], first
    first_path = context.client_root / first["receipt"]["path"]
    first_bytes = first_path.read_bytes()
    other_root = tmp_path / "independent-workspace/EveJS-B"
    other_mod = other_root / "mods/DLSS5"
    shutil.copytree(context.mod_folder, other_mod)
    other_descriptor = read_api_manifest(other_root, other_mod)
    other_context = ModSettingsContext(other_root, other_mod, context.client_root)
    other_request = json.loads(json.dumps(request))
    other_request["requestId"] = str(uuid.uuid4())
    other_request["runtime"]["evejsRoot"] = str(other_root)
    other_request["mod"].update(identity=other_descriptor.identity, root=str(other_root), path=str(other_mod))
    second = invoke(tmp_path, (other_context, other_descriptor, other_request))
    assert second["success"], second
    second_path = context.client_root / second["receipt"]["path"]
    assert first_path != second_path and first_path.read_bytes() == first_bytes
    assert json.loads(first_bytes)["evejsRoot"] == str(context.evejs_root)
    assert json.loads(second_path.read_bytes())["evejsRoot"] == str(other_root)


def test_removing_one_attachment_reports_it_detached_while_other_keeps_payload(tmp_path, profile):
    context, _, request = profile
    request.update(action="prepare_remove", profile=None)
    journal_path = context.client_root.parent / "_evejs/dlss5/install/active-install.json"
    journal = json.loads(journal_path.read_text())
    journal["evejsRoot"] = str(tmp_path / "other-server")
    journal["serverAttachments"] = [dict(root=str(context.evejs_root), status="attached"), dict(root=journal["evejsRoot"], status="attached")]
    journal_path.write_text(json.dumps(journal))
    manager = context.mod_folder / "EveJS-Integration/Manage-EveJSDLSS5.ps1"
    manager.write_text(r'''param($Action,$Profile,$ClientRoot,$EveJSRootPath,$WorkspaceRoot)
$path=Join-Path (Split-Path -Parent $ClientRoot) '_evejs\dlss5\install\active-install.json'
$journal=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
foreach ($row in $journal.serverAttachments) { if ($row.root -eq $EveJSRootPath) { $row.status='detached' } }
$journal | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path
''')
    result = invoke(tmp_path, profile)
    assert result["success"] and result["receipt"]["state"] == "restored", result
    current = json.loads(journal_path.read_text(encoding="utf-8-sig"))
    assert current["status"] == "installed"
    assert [row["status"] for row in current["serverAttachments"]] == ["detached", "attached"]


def test_recovery_with_missing_original_server_does_not_uninstall_other_attachment(tmp_path, profile):
    context, _, request = profile
    request.update(action="recover", profile=None)
    journal_path = context.client_root.parent / "_evejs/dlss5/install/active-install.json"
    journal = json.loads(journal_path.read_text())
    journal["evejsRoot"] = str(tmp_path / "missing-original-server")
    journal["serverAttachments"] = [dict(root=str(context.evejs_root), status="attached")]
    journal_path.write_text(json.dumps(journal))
    manager = context.mod_folder / "EveJS-Integration/Manage-EveJSDLSS5.ps1"
    manager.write_text("param($Action,$Profile,$ClientRoot,$EveJSRootPath,$WorkspaceRoot)\nAdd-Content -LiteralPath (Join-Path $ClientRoot 'actions.txt') -Value $Action\n")
    result = invoke(tmp_path, profile)
    assert result["success"] and result["receipt"]["state"] == "active", result
    assert (context.client_root / "actions.txt").read_text().splitlines() == ["Recover", "VerifyClient"]
