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

- [ ] P/Invoke `libryzenadj` through a narrow core adapter.
- [ ] Detect CPU family, SMU interface, PM table, and supported fields.
- [ ] Implement AC/battery target application with read-back verification.
- [ ] Implement safe shutdown and single-instance behavior.
- [ ] Add diagnostic logging.

## M3: Native GUI

- [ ] Migrate the current WinForms layout.
- [ ] Add tray menu, close-to-tray, and single-instance wake-up.
- [ ] Show effective limits and firmware clamps.
- [ ] Add editable presets and profile-aware ranges.
- [ ] Add worker connection state and restart action.

## M4: Compatibility

- [ ] Add detection profiles for supported AMD mobile generations.
- [ ] Create a hardware matrix with verified, experimental, and unsupported
  states.
- [ ] Add a diagnostics export that contains no secrets.
- [ ] Test at least two physical AMD laptops when available.

## M5: Packaging

- [ ] Portable ZIP build.
- [ ] Installer with scheduled-task setup.
- [ ] Upgrade and uninstall flow.
- [ ] Version metadata and embedded icons.
- [ ] GitHub Actions release artifacts.

## M6: Release Documentation

- [ ] README screenshots.
- [ ] Installation and recovery guide.
- [ ] Supported hardware guide.
- [ ] Security and driver warning.
- [ ] Third-party notices.

## M7: Public Launch

- [ ] Release candidate validation.
- [ ] Chinese project introduction.
- [ ] Feature screenshots and terminal-free demo recording.
- [ ] Promotional video script and rendered video.
- [ ] GitHub release.
- [ ] Bilibili upload and description.

