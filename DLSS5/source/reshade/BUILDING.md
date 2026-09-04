# Native V11 candidate: process-local NR state and acknowledgements

This is an isolated candidate, not an installed or runtime-accepted release.
The preserved V10 source and all installed/frozen packages were left unchanged.

## Source identity

- Upstream: https://github.com/crosire/reshade.git
- Base commit: `18deaa52de0c425a78b329e9cb3c497281cd00ec` (`v6.8.0`).
- Complete derivative: `reshade-6.8.0-evejs-v11.patch`, including the original
  lifetime guard, foreground-only F6 policy, process-local input bridge and new
  read-only NR state/acknowledgement observer.
- Native file/product version: `6.8.0.10` / `6.8.0 UNOFFICIAL`.
- `version-6.8.0.10.h` is the explicit generated header used for both builds.
- All eleven submodules remain at their original upstream gitlink commits.
- Applying the complete patch to the pristine upstream targets reproduces all
  ten compiled source files exactly; this includes both production helpers and
  the native test source.
- No source downloads were performed. The isolated copy includes the preserved
  generated GLAD C/header files, so the GLAD generation/pip target is skipped.

V11 observes recognized messages from the registered RenoDX module before
ReShade writes them to a file. Module identity must match the add-on beside the
current executable; Windows file identity permits launcher junction aliases.
The observer accepts bounded exact F6 messages and the captured initial
active-settings message shape, never a sibling log or persisted INI value.

`EveJSDLSS5QueryNRState` returns a coherent 32-byte ABI1 snapshot under one private
mutex: UNKNOWN/OFF/ON, state/toggle sequences, last toggle state and add-on epoch.
It validates a current-process HWND and exact output size. Unload/replacement
invalidates state. Key injection itself never claims a successful NR change.
The new export uses ordinal502; all501 previous export slots remain unchanged,
including the F6 input bridge at75. No new imports were introduced.

V10's F6 adapter/helper and D3D12 lifecycle guards are byte-identical. Physical
F6 still requires foreground ownership and a foreground UP before rearming.
Synthetic F6 still works process-locally in background clients. The new hidden
self-test executes the existing294 F6 production-policy checks,42 NR tracker
checks and real readonly query ABI checks without injecting keys or showing UI.

## Known limits

Focus is sampled, not globally hooked. A complete focus-away/back transition
between polls is invisible. Initial DOWN, or DOWN immediately after observed
focus loss, is deliberately ignored until a foreground UP is observed. Very
short input pulses may be missed by a polling consumer as before. No claim of
event-perfect key ownership or live game validation is made by the native test.
The state observer reports authenticated local add-on messages, not an independent
GPU fence. The hidden app has no external add-on and cannot prove actual RenoDX
registration, initial-state arrival or one-/two-client rendering transitions.

## Verified toolchain and build commands

- MSBuild `17.14.40.60911`.
- VS2022 MSVC toolset directory `14.44.35207`.
- Compiler `19.44.35228.0`, linker `14.44.35228.0`.
- Windows SDK `10.0.26100.0`; RC/FXC `10.0.26100.7705`.

From the reconstructed V11 source directory, with the recorded header already in
`res/version.h` and all preserved dependencies available:

Reconstruct the derivative from the recorded upstream commit and submodules,
apply `reshade-6.8.0-evejs-v11.patch`, and copy `version-6.8.0.10.h` to
`res/version.h`. The small runtime package does not include a full upstream
checkout or generated dependency cache; the offline recipe assumes those
prerequisites are already available.

```powershell
$msbuild = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe'
Remove-Item Env:PATH -ErrorAction SilentlyContinue
$env:PIP_NO_INDEX = '1'
$env:MSBUILDDISABLENODEREUSE = '1'
& $msbuild .\ReShade.sln /t:ReShade '/p:Configuration=Release App' /p:Platform=64-bit /p:PreBuildEventUseInBuild=false /p:WindowsTargetPlatformVersion=10.0.26100.0 /m:1 /nr:false /nologo /v:minimal
if ($LASTEXITCODE -ne 0) { throw 'Release App build failed' }
$test = Start-Process -FilePath '.\bin\x64\Release App\ReShade64.exe' -ArgumentList '-evejs-dlss5-state-self-test' -WorkingDirectory '.\bin\x64\Release App' -WindowStyle Hidden -PassThru -Wait
if ($test.ExitCode -ne 0) { throw "Native self-test failed: $($test.ExitCode)" }
& $msbuild .\ReShade.sln /t:ReShade /p:Configuration=Release /p:Platform=64-bit /p:PreBuildEventUseInBuild=false /p:WindowsTargetPlatformVersion=10.0.26100.0 /m:1 /nr:false /nologo /v:minimal
if ($LASTEXITCODE -ne 0) { throw 'Release DLL build failed' }
```

The pre-build event is explicitly disabled to stop upstream's version script
incrementing the header between the test application and DLL builds.

Host-specific environment issue: the tool shell inherited both `Path` and
`PATH`, making MSBuild child-process creation fail with MSB6001. Only in the
ephemeral build shell, `Remove-Item Env:PATH` removed the duplicate while leaving
`Path` present. `/m:1 /nr:false` avoided previously launched worker nodes carrying
the duplicate environment. No persistent user/system environment was changed.
The initial failure logs and final successful logs are retained separately.

Expected upstream warnings include C4530 (exception unwind semantics) and X3571
(shader pow with potentially negative input). They were not broadened into an
unrelated compiler-policy change.

No byte-for-byte reproducible-build claim is made: ordinary PE timestamps and
linker settings are retained. A new DLL hash requires manual one-/two-client
F6/automatic transition testing before promotion, including display modes and
held-key focus handoffs. Never weaken payload trust to accept arbitrary DLLs.

The complete upstream BSD-3-Clause notice is included at
`../../THIRD-PARTY-NOTICES/ReShade-BSD-3-Clause.txt`.
