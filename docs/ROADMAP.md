# Roadmap

## M0: Repository Baseline

- [x] Initialize the empty repository.
- [x] Define project goals and safety boundaries.
- [x] Add architecture and status documentation.
- [x] Add solution and project structure.
- [x] Add CI build.

## M1: Core Contracts

- [x] Define named pipe commands and responses.
- [x] Define telemetry models.
- [x] Add validation and unit tests.
- [x] Add profile schema.

## M2: Privileged Worker

- [x] P/Invoke `libryzenadj` through a narrow adapter behind `--enable-hardware`.
- [x] Add RyzenAdj source submodule and reproducible Windows build script.
- [x] Detect CPU family, SMU interface, PM table, and supported fields.
- [x] Expose read-only capability and telemetry snapshots over the named pipe.
- [x] Implement validated target writes with mandatory read-back and restore.
- [x] Implement AC/battery target application with read-back verification.
- [x] Implement safe shutdown and single-instance behavior.
- [ ] Add diagnostic logging.

## M3: Native GUI

- [x] Migrate the current WinForms layout.
- [x] Add tray menu, close-to-tray, and single-instance wake-up.
- [x] Show effective limits and firmware clamps.
- [x] Add editable presets and profile-aware ranges.
- [x] Add worker connection state and automatic restart after conflicts clear.

## M4: Compatibility

- [ ] Add detection profiles for supported AMD mobile generations.
- [x] Create a hardware matrix with verified, experimental, and unsupported
  states.
- [x] Add a diagnostics export that contains no secrets.
- [ ] Test at least two physical AMD laptops when available.

## M5: Packaging

- [x] Portable ZIP build.
- [x] Installer with scheduled-task setup.
- [x] Upgrade and uninstall flow.
- [ ] Version metadata and embedded icons.
- [x] GitHub Actions release artifacts.

## M6: Release Documentation

- [x] README screenshot.
- [x] Installation and recovery guide.
- [x] Supported hardware guide.
- [x] Security and driver warning.
- [ ] Third-party notices.

## M7: Public Launch

- [ ] Release candidate validation.
- [ ] Chinese project introduction.
- [ ] Feature screenshots and terminal-free demo recording.
- [ ] Promotional video script and rendered video.
- [ ] GitHub release.
- [ ] Bilibili upload and description.

