# Native Release Candidate Status

Status: `STABLE_LOCAL_DEPLOYED`

This document tracks the native Rust GUI + C++ worker package and its
stable-local deployment. `C:\RyzenAdj` currently holds `1.0.20-native`
(commit `d9129b0`, compact 600x360 UI polish, input-draft retention, and
advanced work-area scrolling). `1.0.19-native` is preserved as
`C:\RyzenAdj.before-v1.0.20-native-20261112-ui`, `1.0.18-native` as
`C:\RyzenAdj.before-v1.0.19-native-20261112-ui`. The
previous native `1.0.17-native` build is preserved as
`C:\RyzenAdj.before-20261112-074413`, `1.0.16-native` as
`C:\RyzenAdj.before-20261112-070824`, `1.0.15-native` as
`C:\RyzenAdj.before-20261112-064143`, `1.0.14-native` as
`C:\RyzenAdj.before-20261112-063328`, `1.0.13-native` as
`C:\RyzenAdj.before-20261112-062726`, `1.0.12-native` as
`C:\RyzenAdj.before-20261112-055844`, `1.0.11-native` as
`C:\RyzenAdj.before-20261112-055115`, `1.0.10-native` as
`C:\RyzenAdj.before-20261112-052733`, `1.0.9-native` as
`C:\RyzenAdj.before-20261112-041014`, `1.0.8-native` as
`C:\RyzenAdj.before-20261112-033749`, and `1.0.7-native` as
`C:\RyzenAdj.before-20261112-025316`, `1.0.6-native` as
`C:\RyzenAdj.before-20261112-023730`, `1.0.5-native` as
`C:\RyzenAdj.before-20261112-022356`, the earlier `1.0.4-native` build as
`C:\RyzenAdj.before-20261112-015439`, the `1.0.3-native` builds as
`C:\RyzenAdj.before-20261112-011649` and
`C:\RyzenAdj.before-20261112-005635`, `1.0.2-native` as
`C:\RyzenAdj.before-20261112-003929`, and `1.0.1-native` as
`C:\RyzenAdj.before-20261111-233609`, `1.0.0-native` as
`C:\RyzenAdj.before-20261111-232010`, and the .NET `1.0.4` package as
`C:\RyzenAdj.before-20261111-223017`.

Decision (2026-11-12): the native line has a hardware-gated stable-local
candidate for the verified 8845HS platform, and `C:\RyzenAdj` now contains the
`1.0.18-native` package. Broader AMD generation support remains experimental.
The current local publication readiness gate is `PASS` with all 13 checks true,
with
`PublicReleaseReadiness=READY_FOR_HUMAN_REVIEW` and no local blockers. Evidence:
`docs/evidence/release/native-publication-readiness-1.0.18-2026-11-12.json`.

Note (2026-11-12): `1.0.18-native` is the first package gated with
`-VerifyWorkerHang`, which runs the maintained hang verifier against the
expanded package. `1.0.17-native` added hung-worker replacement on top of the
30 s heartbeat watchdog. A worker that stops answering is terminated from a
background thread and respawned, then the saved battery/AC policy is restored;
the GUI window remains responsive even while a driver-bound worker is being
replaced. `1.0.16-native` added worker supervision with automatic
policy restore and a probe that retries `ERROR_PIPE_BUSY`. `1.0.13-native` added the packaged headless
`amd-mobile-power-probe.exe` and makes the GUI, probe, worker, and portable ZIP
byte-reproducible from the same commit. `1.0.12-native` was the first release
whose deployed binaries matched a verified rebuild. `1.0.10-native` supersedes `1.0.9-native` by keeping the
target editor synchronized with the active preset at startup and during policy
refresh. `1.0.9-native` itself superseded `1.0.8-native` by correcting the
target input after profile clamping. `1.0.8-native` supersedes `1.0.7-native`
by waiting for an
app-owned driver to reach `Stopped` before replacing its `.sys` file and by
making the UI verifier wait for advanced-mode policy controls. `1.0.7-native`
added a safe `uninstall-driver-bootstrap.ps1` and an installer that reuses an
existing WinRing0 service rather than replacing another installation's binary
path.
`1.0.6-native` added the package-local elevated `install-driver-bootstrap.ps1`
for fresh Windows hosts. `1.0.5-native` added deterministic 100/125/150%
logical DPI layout fixtures executed against the packaged GUI.
`1.0.4-native` added the family-indexed multi-generation profile catalog,
read-only `getProfiles`, complete-catalog compatibility reports, and
report-import validation. Every RyzenAdj family `0-15` maps to exactly one
conservative fallback while `8845HS + 4c0009` remains the sole verified device
profile. Worker version is `0.6.0-native`. The local shortcut launches with
`--enable-write-controls --simple-mode --max-target-watts 45`; saved presets
are `10/25/45 W`, the automatic battery/AC policy is disabled, and `10 W` is
the manual night preset. `1.0.3-native` added per-monitor DPI awareness, a
resizable native window, hand cursors, a protected metric band, and the
uniform policy. `1.0.2-native` added the embedded
PE icon (`RT_ICON` + `RT_GROUP_ICON` 1). `1.0.1-native` fixed the desktop
shortcut exiting immediately with `unknown argument: --simple-mode`. The native
parser accepts `--simple-mode` / `--advanced-mode`,
`--max-target-watts <N>`, and `--uniform-target-watts <N>`;
`native/gui-cli-contract.json` remains the single source of truth, and the
publication-readiness gate launches the deployed GUI with the real shortcut
arguments under an isolated `%LocalAppData%` and a unique worker pipe.
`1.0.0-native` remains the
historical candidate: it contains the complete
break-and-rebuild UI: one continuous dark command deck shared by simple and
advanced modes, a flat simple telemetry ledger, a split advanced workspace,
and live STAPM/Fast/Slow read-back. It also adds test-only failure-state
fixtures for worker offline, firmware clamp, unsupported platform, and long
error, with write-control state assertions. The advanced policy now supports
`仅电池`, which skips AC/external writes entirely. The new high-contrast
fixture renders the complete shell with black surfaces, white text, yellow
structure, and black text on yellow primary actions without changing Windows
accessibility settings.

## Current Candidate

```text
artifacts/native-packages/amd-mobile-power-v1.0.20-native-win-x64-native-preview.zip
```

- Size: `758,548` bytes.
- SHA256:
  `4285011dee71e3fbdc9c36869079e54430bccaee168d8d5f0f99b9524d88adf0`.
- Source commit: `d9129b01f4039ebd4db547070612589a1d834936`.
- Working tree at build time: clean.
- Reproducibility: GUI `72b22832`, probe `9750418f`, worker `67af1d41`, and the
  ZIP itself are byte-identical across two builds.
- Policy write verification: same-value battery probe at `25/25/20 W`.
- Worker-hang replacement: verified separately on 2026-11-13 against the
  packaged 1.0.20 pair (`33.5 s`, 20 responsive samples, 0 failures, policy
  restored to `10/10/10 W`; the hardware was already at 10 W).
- Supersedes `1.0.19-native` (package `f9825bb915e79ada5a61b19e1a30ac507f6aa3fc81e5190422f678116a5b4d6c`,
  source `18dbec11cd6f7045edc9ff866b56fb5cde95f724`), which added the compact
  600x360 polish; `1.0.20-native` adds the advanced work-area fit with
  full-content scrolling and the minimum-width clamp fix.

Local review bundle:

```text
artifacts/native-release-review/v1.0.18-native
```

The bundle is `REVIEW_ONLY` and is not a public release.

Historical candidate `1.0.7-native` remains recorded with package SHA256
`a018e1af1a82a5be1dc1cee4fa54cf419d35a778cd056a16a5a35a34262635c4`
and source commit `01cdb506415b0b7fc4b39d7e328f8f282c9696cf`.

Historical candidate `1.0.6-native` remains recorded with package SHA256
`1bb6fbb5e3ff0dd7223cd47a95211fed4b71c6d360f4343700fb2999fbb7321d`
and source commit `a9c02aa1dcc7722c71ccc37a9f55ce82ae32ee6e`.

Historical candidate `1.0.5-native` remains recorded with package SHA256
`a0db74b65be3be165c3587beeb61682d7a44db3b584c04622f23d1ca4102ba60`
and source commit `22a062479a1c9f162ca8baf6cd21309684681b20`.

Historical candidate `1.0.4-native` remains recorded with package SHA256
`0f6889803372c70436d3e61b16b544a53ec7b9b87de75d563fd11a117ddcc70e`
and source commit `6e9e10c3207660fd5f878b389187ceaa91c9f396`.

Historical candidate `1.0.3-native` remains recorded with package SHA256
`2935779907f89d38c0ca7d1a46a9661de6a18b32b6bf8bb7083bedff74807b8e`
and source commit `e26ede44aab40bea8b2470edf9203f9c94b70054`.

Historical candidate `1.0.2-native` remains recorded with package SHA256
`614743257e66c002b5873e3bc5f36f57a874bf763e6a3cb728a28225eec16d9c`
and source commit `545f6bcc2e116e667cad0f87331d97b5b9284c2a`.

Historical candidate `1.0.1-native` remains recorded with its exact package
SHA256
`992290ffb2337038c937932e2a4888db19946df46c2678b7a32b33285f997cad`
and source commit `442309753f6965a4ba01ff0ae4f34e81280f34e5`.

Historical candidate `1.0.0-native` remains recorded with its exact package
SHA256
`f3fd6ea1d1b0292c6ec9ea7445f191adc302066f78a728528a3722923c73a0bf`
and source commit `ddb7d9cba3195f4a16df1299215a9e26cd18544f`.

## Passed Gates

- Rust GUI lifecycle, three Win32 minimize/restore cycles, close-to-tray, tray
  restore, single-instance wake-up, diagnostics export, view switching,
  topmost, and editable preset persistence.
- Rust unit tests: 41/41 passed, including a contract test that parses every
  entry in `native/gui-cli-contract.json` and a regression test for the
  desktop shortcut arguments and uniform 10 W policy.
- Rust formatting and Clippy with `-D warnings`.
- C++ power-limit policy and battery/AC policy tests.
- Read-only hardware capability and telemetry probe on Ryzen 7 8845HS on AC:
  Hawk Point family `10`, PM table `4c0009`, profile
  `hawk-point-8845hs`, limits `10/10/10 W`.
- `1.0.18-native` clean package verification (19 checksum entries), isolated
  install/uninstall, shell integration, DPI fixtures, packaged headless probe,
  and a controlled current-value policy probe pass. The deployed UI shows
  target editor `10`, effective range `5-10 W`, one visible `10 W` preset, and
  live `10/10/10 W` read-back.
- The headless probe runs from the expanded ZIP with the GUI closed:
  `collectionStatus=PASS`, `hardwareInitialized=true`, write controls disabled,
  matched `hawk-point-8845hs`, live AC `10/10/10 W`.
- Reproducibility gate: GUI, probe, C++ worker, and the portable ZIP are
  byte-identical across two builds of the same commit.
- Worker supervision: killing the deployed worker produced a replacement in
  `1.3 s`; the saved policy was re-applied (`enabled=true`, both targets
  `10/10/10`) and the pipe served `10/10/10 W` again. The probe answered
  `30/30` calls while the GUI polled.
- Hung-worker replacement: `NtSuspendProcess` held the isolated worker for
  `34.5 s`; the GUI stayed `Responding=true`, a replacement worker appeared,
  and the saved policy was re-applied (`enabled=true`, both targets
  `10/10/10`, `lastAttemptSucceeded=true`). Termination and the bounded wait
  run off the UI thread.
- The hang check is now repeatable: `native/verify-worker-hang.ps1` refuses to
  run beside another hardware owner, starts an isolated GUI/worker pair,
  suspends the worker, samples GUI responsiveness every second, and requires
  the replacement to restore the 10 W policy. `verify-release.ps1
  -VerifyWorkerHang` runs it against the expanded package.
- `1.0.18-native` is the first package gated with `-VerifyWorkerHang`:
  replacement in `34.9 s`, `28/28` responsive samples, zero failures, and the
  10/10/10 W policy restored.
- Native read-only write guard: invalid target rejected, no write requested.
- Battery-authorized dry-run write guard: PASS with
  `ExecuteNoChangeWrite=Not requested`.
- `1.0.8-native` clean package verification with 18 checksum entries,
  isolated install/overwrite/uninstall, extracted GUI/worker read-only
  verification, compatibility JSON/Markdown collection, and
  `PolicyWriteVerification=Skipped`.
- The package includes safe WinRing0 install and uninstall helpers; package
  verification requires both, and all 19 deployed payload files match.
- The driver bootstrap waits for an app-owned service to stop before replacing
  its `.sys` file and attempts a restart if replacement/configuration fails.
- The UI verifier passed three consecutive policy-control runs after adding
  readiness waits for the battery-only and policy-enable buttons.
- Real current-user Start menu, Startup shortcut, and uninstall-entry
  create/remove cycle.
- Cross-version upgrade from `rc.17` to `1.0.0-native`: installed payload matched the
  new archive, upgraded GUI/worker passed read-only verification, and uninstall
  removed the installation directory.
- Foreground-verified screenshot capture for simple, advanced, and read-only
  states at 125% Windows scaling.
- Failure-state and battery-only screenshots with machine-checked
  target/preset/diagnostics availability. No hardware worker is started for
  these fixtures.
- Focused-input captures with the actual child focus verified, plus diagnostics
  checks for active mode, topmost state, taskbar icon availability, and tray
  icon id.
- High-contrast simple and advanced captures with `ui.highContrast=true`, no
  hardware worker startup, and the same target/preset/diagnostics availability
  checks as the other write-controls fixtures.
- Extracted `1.0.8-native` packaged GUI/worker verification with GUI and worker
  hashes, three minimize/restore cycles, close-to-tray, tray restore,
  single-instance wake, `taskbarIconAvailable=true`, `trayIconId=1`, and the
  persisted `simple` to `advanced` mode transition.
- Controlled policy probe requested the live AC limits `10/10/10 W`, verified
  the worker read-back, disabled the policy, and shut down cleanly. Live limits
  remained `10/10/10 W`.
- Embedded-icon gate: the built, staged, and deployed GUI each carry
  `RT_GROUP_ICON` 1 with 9 `RT_ICON` images, and the 32x32 icon extracted from
  the deployed exe matches `assets/amd-mobile-power.ico` with zero pixel
  differences. `build.ps1`, `build-package.ps1`, and the readiness gate all fail
  on a missing icon.
- The verified package is deployed at `C:\RyzenAdj` with the prior
  `1.0.7-native` build at
  `C:\RyzenAdj.before-20261112-025316`, `1.0.6-native` at
  `C:\RyzenAdj.before-20261112-023730`, `1.0.5-native` at
  `C:\RyzenAdj.before-20261112-022356`, `1.0.4-native` at
  `C:\RyzenAdj.before-20261112-015439`, earlier `1.0.3-native` builds at
  `C:\RyzenAdj.before-20261112-011649` and
  `C:\RyzenAdj.before-20261112-005635`, `1.0.2-native` at
  `C:\RyzenAdj.before-20261112-003929`, and `1.0.1-native` at
  `C:\RyzenAdj.before-20261111-233609`, `1.0.0-native` at
  `C:\RyzenAdj.before-20261111-232010`, and the .NET `1.0.4` directory at
  `C:\RyzenAdj.before-20261111-223017`. The deployed GUI/worker passed
  read-only worker, lifecycle, tray, single-instance, mode, preset,
  battery-only, and diagnostics checks; the desktop shortcut keeps
  `--enable-write-controls --simple-mode --max-target-watts 45`.
- Profile-catalog gate: the worker reports 10 entries, exactly one verified
  profile, and exactly one family fallback for every RyzenAdj family `0-15`.
  The packaged read-only collector returned `PASS` with worker
  `0.6.0-native`, matched `hawk-point-8845hs`, and live `10/10/10 W` limits;
  the importer accepted the report and rejected a synthetic catalog missing
  family `8`.
- DPI layout gate: the packaged GUI rendered simple and advanced shells at
  logical 100/125/150% with exact client sizes `640x392`/`780x680`,
  `800x490`/`975x850`, and `960x588`/`1170x1020`. Separate region inspection
  found no clipped header, target, preset, metric, or status text. Real
  100%/150% Windows sessions remain an external open gate.
- Desktop-shortcut launch gate: the promotion helper launched the promoted GUI
  with the real shortcut arguments under an isolated `%LocalAppData%` and a
  unique worker pipe, and reported `LaunchVerification=PASS` with window title
  `AMD Mobile Power`. The final readiness gate performs the same check against
  `C:\RyzenAdj`, including value-bearing `--max-target-watts 10` and
  `--uniform-target-watts 10`, and reports `LocalReadiness=PASS`,
  `PublicReleaseReadiness=READY_FOR_HUMAN_REVIEW`, and
  `BlockersFromLocalChecks=[]`.
- Added a local compatibility-report importer that rejects non-read-only,
  incomplete-privacy, path-leaking, and duplicate reports; the first rc.17
  report is archived under `docs/evidence/compatibility` and indexed in
  `docs/COMPATIBILITY_REPORTS.md`.

## Evidence

- `docs/evidence/packaging/v1.0.18-native-clean-2026-11-12.json`
- `docs/evidence/packaging/v1.0.18-native-release-gate-2026-11-12.json`
- `docs/evidence/packaging/v1.0.18-native-shell-integration-2026-11-12.json`
- `docs/evidence/packaging/v1.0.18-native-deployment-2026-11-12.json`
- `docs/evidence/hardware/v1.0.18-native-power-policy-no-change-2026-11-12.json`
- `docs/evidence/hardware/v1.0.18-native-worker-hang-2026-11-12.json`
- `docs/evidence/hardware/v1.0.18-native-worker-hang-clean-2026-11-12.json`
- `docs/evidence/ui/native-packaged-1.0.18-native-ui-2026-11-12.json`
- `docs/evidence/packaging/v1.0.17-native-watchdog-hang-2026-11-12.json`
- `docs/evidence/packaging/v1.0.17-native-clean-2026-11-12.json`
- `docs/evidence/packaging/v1.0.17-native-release-gate-2026-11-12.json`
- `docs/evidence/packaging/v1.0.17-native-shell-integration-2026-11-12.json`
- `docs/evidence/packaging/v1.0.17-native-deployment-2026-11-12.json`
- `docs/evidence/hardware/v1.0.17-native-power-policy-no-change-2026-11-12.json`
- `docs/evidence/hardware/v1.0.17-native-worker-hang-verifier-2026-11-12.json`
- `docs/evidence/ui/native-packaged-1.0.17-native-ui-2026-11-12.json`
- `docs/evidence/packaging/v1.0.16-native-clean-2026-11-12.json`
- `docs/evidence/packaging/v1.0.16-native-release-gate-2026-11-12.json`
- `docs/evidence/packaging/v1.0.16-native-shell-integration-2026-11-12.json`
- `docs/evidence/packaging/v1.0.16-native-deployment-2026-11-12.json`
- `docs/evidence/hardware/v1.0.16-native-power-policy-no-change-2026-11-12.json`
- `docs/evidence/ui/native-packaged-1.0.16-native-ui-2026-11-12.json`
- `docs/evidence/packaging/v1.0.13-native-clean-2026-11-12.json`
- `docs/evidence/packaging/v1.0.13-native-release-gate-2026-11-12.json`
- `docs/evidence/packaging/v1.0.13-native-shell-integration-2026-11-12.json`
- `docs/evidence/packaging/v1.0.13-native-deployment-2026-11-12.json`
- `docs/evidence/hardware/v1.0.13-native-power-policy-no-change-2026-11-12.json`
- `docs/evidence/build/reproducibility-2026-11-12.json`
- `docs/evidence/diagnostics/headless-probe-8845hs-live-2026-11-12.json`
- `docs/evidence/packaging/v1.0.10-native-clean-2026-11-12.json`
- `docs/evidence/packaging/v1.0.10-native-release-gate-2026-11-12.json`
- `docs/evidence/packaging/v1.0.10-native-shell-integration-2026-11-12.json`
- `docs/evidence/hardware/v1.0.10-native-power-policy-no-change-2026-11-12.json`
- `docs/evidence/ui/native-deployed-1.0.10-capture-2026-11-12.json`
- `docs/evidence/packaging/v1.0.8-native-clean-2026-11-12.json`
- `docs/evidence/packaging/v1.0.8-native-release-gate-2026-11-12.json`
- `docs/evidence/packaging/v1.0.8-native-shell-integration-2026-11-12.json`
- `docs/evidence/hardware/v1.0.8-native-power-policy-no-change-2026-11-12.json`
- `docs/evidence/packaging/v1.0.8-native-deployment-2026-11-12.json`
- `docs/evidence/ui/native-packaged-1.0.8-native-ui-2026-11-12.json`
- `docs/evidence/ui/native-deployed-1.0.8-native-ui-2026-11-12.json`
- `docs/evidence/ui/native-dpi-100-125-150-2026-11-12.json`
- `docs/evidence/compatibility/mechrevo-wujie15-pro-20261112-011617.json`
- `docs/evidence/release/native-publication-readiness-1.0.18-2026-11-12.json`
- `docs/assets/native-exe-icon-2026-11-11.png`
- `native/rust-gui/build.rs`
- `native/check-exe-icon.ps1`
- `docs/evidence/packaging/v1.0.1-native-clean-2026-11-11.json`
- `docs/evidence/packaging/v1.0.1-native-release-gate-2026-11-11.json`
- `docs/evidence/packaging/v1.0.1-native-shell-integration-2026-11-11.json`
- `docs/evidence/hardware/v1.0.1-native-power-policy-no-change-2026-11-11.json`
- `docs/evidence/packaging/v1.0.1-native-deployment-2026-11-11.json`
- `docs/evidence/ui/native-packaged-1.0.1-native-ui-2026-11-11.json`
- `docs/evidence/ui/native-deployed-1.0.1-native-ui-2026-11-11.json`
- `native/gui-cli-contract.json`
- `docs/evidence/packaging/v1.0.0-native-clean-2026-11-11.json`
- `docs/evidence/packaging/v1.0.0-native-release-gate-2026-11-11.json`
- `docs/evidence/packaging/v1.0.0-native-shell-integration-2026-11-11.json`
- `docs/evidence/packaging/v1.0.0-native-cross-version-upgrade-2026-11-11.json`
- `docs/evidence/hardware/v1.0.0-native-power-policy-no-change-2026-11-11.json`
- `docs/evidence/packaging/v1.0.0-native-deployment-2026-11-11.json`
- `docs/COMPATIBILITY_REPORTS.md`
- `docs/evidence/compatibility/index.json`
- `docs/evidence/ui/native-redesign-2026-11-11.json`
- `docs/evidence/ui/native-ui-failure-states-2026-11-11.json`
- `docs/evidence/ui/native-battery-only-policy-2026-11-11.json`
- `docs/evidence/ui/native-battery-only-capture-2026-11-11.json`
- `docs/evidence/ui/native-focus-2026-11-11.json`
- `docs/evidence/ui/native-high-contrast-2026-11-11.json`
- `docs/evidence/ui/native-packaged-1.0.0-ui-2026-11-11.json`
- `assets/native-gui-redesign-simple-2026-11-11.png`
- `assets/native-gui-redesign-advanced-2026-11-11.png`
- `assets/native-gui-redesign-readonly-simple-2026-11-11.png`
- `assets/native-gui-redesign-readonly-advanced-2026-11-11.png`
- `assets/native-battery-only-simple-2026-11-11.png`
- `assets/native-battery-only-advanced-2026-11-11.png`
- `assets/native-focus-simple-2026-11-11.png`
- `assets/native-focus-advanced-2026-11-11.png`
- `assets/native-high-contrast-simple-2026-11-11.png`
- `assets/native-high-contrast-advanced-2026-11-11.png`

Superseded candidates keep their exact historical package and evidence.

## Open Gates

- Obtain read-only compatibility evidence from a different AMD laptop or
  generation when a second device becomes available; no second machine is
  currently available.
- Logical UI layout fixtures now pass at 100%, 125%, and 150% without changing
  system settings; repeat the matrix in real 100%/150% Windows sessions, plus
  focused-input states.
- Observe a successful hosted Windows CI run. The current external blocker is
  the repository account billing/spending limit.
- Verify WinRing0 behavior under a clean Windows security baseline.
- Final human review before any promotion or public release.

## Promotion Rule

The native package is stable-local for the verified 8845HS platform.
`C:\RyzenAdj` is replaced only through
`native/promote-stable-deployment.ps1`, which requires the verified package,
keeps a full pre-promotion backup, retargets the existing desktop shortcut while
keeping only `native/gui-cli-contract.json` arguments, launches the promoted GUI
with those real arguments, and rolls back on failure.

Public GitHub Release and Bilibili upload remain unapproved.
