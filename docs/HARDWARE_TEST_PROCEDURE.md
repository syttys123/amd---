# Controlled Hardware Test Procedure

This procedure is for a supervised test on the development laptop. It is not
part of CI and must not be run by an unattended maintenance task.

## Safety Preconditions

- Run only while connected to AC power.
- Use a laptop with a known recovery path and a charged battery.
- Close other RyzenAdj-based tools and vendor power utilities.
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

## Abort Criteria

Stop testing and restore the previous deployment if:

- The machine becomes unstable or unexpectedly shuts down.
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
