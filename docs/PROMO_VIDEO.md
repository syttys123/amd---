# Promotional Video Draft

The native development-preview video is generated from the reviewed screenshots,
not from live hardware during rendering. Rendering starts no application
process and performs no hardware write.

## Current Draft

The current draft is 78.2 seconds at 1920x1080, 25 fps, with H.264 video, AAC
stereo audio, Chinese narration, and simplified-Chinese captions. It uses the
verified `1.0.8-native` 10 W local policy screenshots, including the corrected
target editor and the `5-10 W` effective range. It is marked
`DRAFT_FOR_HUMAN_REVIEW`; it is not approved for upload.

![Promo draft cover](assets/native-promo-10w-cover-2026-11-12.png)

![Seven-scene review contact sheet](assets/native-promo-10w-contact-sheet-2026-11-12.png)

Bilibili 1146x717 cover:

![Bilibili launch cover](assets/bilibili-cover-native-10w-2026-11-12.png)

Local render:

```text
artifacts/media/amd-mobile-power-native-promo-10w-2026-11-12/
  amd-mobile-power-native-intro-10w-2026-11-12.mp4
```

- Size: 22,129,812 bytes.
- SHA256:
  `af70c9e7bd837c04346dde7110fa7cd0a9c9221edad5f3e5826a28c92ed7d575`.
- Full-file FFmpeg decode: PASS.
- Audio level: mean `-21.2 dB`, peak `-1.1 dB`.
- Title, caption, and bullet safe-width checks: PASS.
- Scene count: 7.

Machine-readable evidence:
`docs/evidence/media/native-promo-10w-draft-2026-11-12.json`.

Verify the local MP4 and every committed review/source hash without rerendering:

```powershell
.\verify-media.ps1 `
  -VideoPath .\artifacts\media\amd-mobile-power-native-promo-10w-2026-11-12\amd-mobile-power-native-intro-10w-2026-11-12.mp4 `
  -ManifestPath .\artifacts\media\amd-mobile-power-native-promo-10w-2026-11-12\promo-manifest.json `
  -EvidencePath .\docs\evidence\media\native-promo-10w-draft-2026-11-12.json
```

The verifier checks the manifest, evidence, SHA256, codecs, dimensions, frame
rate, duration, full decode, mean/peak audio levels, captions, storyboard,
renderer, video cover, contact sheet, and the 1146x717 Bilibili cover.

Regenerate the Bilibili cover:

```powershell
.\render-launch-cover.ps1 `
  -OutputPath .\docs\assets\bilibili-cover-native-10w-2026-11-12.png `
  -ScreenshotPath .\assets\native-gui-10w-simple-2026-11-12.png `
  -Eyebrow "AMD NATIVE / OPEN SOURCE" `
  -PreviewLabel "1.0.8 / LOCAL 10 W" `
  -Subtitle "电池与插电统一 · 实时回读" `
  -PillText "原生 GUI|只读默认|兼容诊断" `
  -FooterRight "READ-ONLY BY DEFAULT"
```

The cover uses the verified clean-package screenshot, application icon, and
reviewed launch copy. Rendering fails if the main text exceeds its safe width.

## Render

```powershell
.\render-promo.ps1 `
  -Storyboard .\media\promo-native\storyboard.json `
  -OutputDirectory .\artifacts\media\amd-mobile-power-native-promo-10w-2026-11-12 `
  -OutputName amd-mobile-power-native-intro-10w-2026-11-12.mp4
```

The default output is written under the ignored `artifacts/media` directory:

```text
artifacts/media/amd-mobile-power-native-promo-10w-2026-11-12/
  amd-mobile-power-native-intro-10w-2026-11-12.mp4
  captions-zh.srt
  cover-draft.png
  promo-manifest.json
  review/
    review-01-hook.png ... review-07-closing.png
    contact-sheet.png
```

Generated scene PNGs and WAV files are retained by default for review. Use
`-CleanWorkingFiles` when only the final MP4, captions, cover, manifest, and
review frames are needed.

The renderer enforces scene text bounds before encoding and runs full-decode,
mean-volume, and peak-volume checks before writing the manifest. A failed text
or audio bound stops the render instead of producing an accepted draft.

## Review Gate

- The video is labelled as a development preview.
- It states that only one physical AMD laptop has full evidence.
- It does not claim universal AMD laptop support.
- It does not imply that development builds are ready for unsupervised writes.
- No terminal, personal path, account name, notification, or unrelated desktop
  content appears.
- The project owner reviews the final voice, pacing, claims, and cover before
  any authenticated upload.
