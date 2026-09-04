# Local source generation - 0.5.5

This final-version candidate retains the exact source helpers, templates,
runner, native DLL and generated V12 runtime of the prior 0.5.5-dev candidate.
Only release identity, trust pins and licensing/documentation are finalized.
Neither final package nor matching launcher 1.0.50 is manually accepted yet.

This packaging candidate replaces the two distributed adapted-client method
bodies with source-only templates and a narrow, data-only Python 2.7 emitter.
Only the exact supported client archive is accepted. The emitter derives names,
literals, calls, expressions and statement/control-flow regions from local code
objects. Unsupported shapes, offsets, markers and line slots fail closed.

No original/generated game module or method executes during generation. The
existing pinned local Python runtime runs the authenticated authored builder.
That builder authenticates all helper/template bytes before either helper runs,
loads the emitter and reconstruction source into separate private namespaces,
and compiles the locally completed templates as data. No filesystem helper
imports, package initializers, cached .pyc files, installed decompiler, or new
third-party Python dependency is needed.

The production manager checks the raw manifest, helper, runner/builder sources,
executable, templates and local derivation helpers. Generator inventory is exact;
extra files/directories and reparse points are rejected. Checks also run for
cached payloads and immediately before each of the two generation stages.

## Runtime identity

The source pipeline must generate these unchanged outputs before installation:

| Output | Bytes | SHA-256 |
| --- | ---: | --- |
| Graphics stage | 30,760,389 | `41A380AEF24D7304F595C7F4DBF93B5BD45D2F42A343E6DACD1C0096526A1FB1` |
| Final V12 archive | 30,763,542 | `BC8DD57471B376D3CC37A1908CEE64174E98EDB6D3D94B9F04437BDCE33686CC` |

The final hash pins compiled nested methods, closure layout, line metadata,
marshal representation and archive compression, not merely equivalent-looking
source. Unrelated archive entries and the original executable remain unchanged.
The ReShade DLL, downloaded runtime components, F6 isolation, NR intent and
transition timings are unchanged from 0.5.4.

## Source boundary and limits

Local regions include the original device creation body and the retained/mixed
graphics setup, settings application, renderer calls, readiness expressions,
panel refresh, event emission, window guard and crash-key expression. The
templates retain authored lifecycle/transition/NR policy, not encoded stock
method bodies. Startup template lines 170 and 181 use matching device API
expressions in authored startup policy; these small integration expressions
are documented rather than silently claimed to have been locally substituted.

The templates and emitter are not a general decompiler and do not support
arbitrary newer client builds. No original or patched archive/PYC, local Python
DLL, private reconstructed source, prototype outputs or downloaded NVIDIA/RenoDX
binaries ship in the distribution. Developer tests are excluded too.

Original project contributions are MIT licensed under LICENSE, with the scope
and third-party exclusions in LICENSING.md. The user's client implementation,
generated mixed client methods and third-party components are not relicensed.
Local derivation is not legal clearance or a grant of client modification or
redistribution rights. Source/rights uncertainty and component terms remain
separate publication considerations.

Every changed package or launcher requires fresh manual testing of the exact
new artifacts before publication, even when runtime bytes are identical. The
scope is agreed with the user; no automatic full graphics matrix is imposed.
A successful test alone does not authorize commit, tagging, upload or release.
