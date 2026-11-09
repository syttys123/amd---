# Controlled Hardware Test Procedure

This procedure is for a supervised test on the development laptop. It is not
part of CI and must not be run by an unattended maintenance task.

## Safety Preconditions

- Run only while connected to AC power.
- Use a laptop with a known recovery path and a charged battery.
- Close other RyzenAdj-based tools and vendor power utilities.
- Exit the legacy `RyzenPower` or `ryzenadj` process before starting the new
  worker. Concurrent hardware owners can trigger an access violation in the
  native driver.
- Stop legacy scheduled tasks, including `\AMD\RyzenAdjWatch`, because stopping
  the visible GUI does not stop its hidden worker.
- Confirm `Local\RyzenAdjPowerWorker` is no longer held before starting the new
  worker.
- For migration, disable the legacy logon task and reboot instead of
  force-terminating the hidden worker. See `MIGRATING_FROM_LEGACY.md`.
- Confirm `getSnapshot` reports a supported platform and valid
  STAPM/Fast/Slow limits.
- Keep the stable deployment at `C:\RyzenAdj` unchanged until the test passes.

## First Write Test

The first write test should not change the effective power profile. Use the
exact limit triplet returned by `getSnapshot` as the target:

```text
target = current STAPM/Fast/Slow limits
```

This verifies command transport, native writes, read-back, and restore without
intentionally changing the thermal load.

## Execution

1. Start the worker from a clean Release build with `--enable-hardware`.
2. Record a `getSnapshot` response.
3. Send one `applyTarget` request using the current limit triplet.
4. Verify every read-back is present and finite.
5. For a firmware clamp, record requested and effective values; a lower
   effective value is reported but is not treated as a transport failure.
6. If the request fails, verify the response reports whether previous limits
   were restored.
7. Send a final `getSnapshot` and compare limits with the initial response.
8. Stop the worker and confirm no worker process remains.

## AC/Battery Policy Verification

Use the packaged worker with `verify-power-policy.ps1`. The default mode is a
read-only preflight:

```powershell
.\verify-power-policy.ps1 `
  -PackageDirectory artifacts\packages\amd-mobile-power-v0.1.3-dev-win-x64-lite
```

The full supervised test starts on AC power, records the current AC limits,
asks for the adapter to be unplugged, records the current battery limits, tests
the conservative battery target, verifies the automatic AC transition, and then
restores both baselines. It requires an explicit switch and an interactive
confirmation phrase:

```powershell
.\verify-power-policy.ps1 `
  -PackageDirectory artifacts\packages\amd-mobile-power-v0.1.3-dev-win-x64-lite `
  -BatteryWatts 12 `
  -ConfirmHardwareWrite
```

The script uses an isolated named pipe, disables the policy during baseline
capture and final recovery, sends `shutdown` for graceful teardown, and writes
machine-local evidence below `artifacts\verify`. A full run must be supervised;
do not put it in CI or an unattended automation.

The read-only preflight was exercised on the development laptop on 2026-11-10:
MECHREVO WUJIE15 PRO, Ryzen 7 8845HS, Hawk Point profile, AC baseline
12/12/12 W, zero hardware writes, and a clean worker shutdown. Machine-readable
evidence:
`docs/evidence/hardware/mechrevo-wujie15-8845hs-policy-preflight-2026-11-10.json`.
This preflight does not satisfy the supervised battery/AC transition gate.

## Abort Criteria

Stop testing and restore the previous deployment if:

- The machine becomes unstable or unexpectedly shuts down.
- RyzenAdj reports `Unable to get MP1 SMU Obj`, especially after an owning
  process was force-terminated, or `ryzenadj.exe --info` hangs in SMU polling.
  Reboot before any further hardware access.
- A read-back is missing or non-finite.
- A write reports success but an effective limit rises above the request.
- Automatic restore fails or cannot be verified.
- Windows security software blocks or unloads WinRing0.

## After a Successful Test

- Record the device, BIOS, SMU, PM table, power line, requested limits, effective
  limits, temperatures, and test result in `HARDWARE_MATRIX.md`.
- Keep the worker behind an explicit hardware flag during development.
- Do not promote the build to `C:\RyzenAdj` until GUI and packaging checks also
  pass.

Completed development evidence:

- Device: MECHREVO WUJIE15 PRO, Ryzen 7 8845HS.
- Package: `amd-mobile-power-v0.1.3-dev-win-x64-lite.zip`.
- Result: 12/12/12 W initial, requested, read-back, and final limits; no restore,
  firmware clamp, or STAPM warning; packaged GUI/worker stopped afterward.
- Summary:
  `docs/evidence/hardware/mechrevo-wujie15-8845hs-no-change-2026-11-10.json`.
