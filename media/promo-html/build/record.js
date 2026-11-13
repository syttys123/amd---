// Frame-exact Playwright recorder for the promo HTML timeline.
// Usage:
//   node record.js <html-path> <frames-dir> [--fps 30] [--width 1920]
//       [--height 1080] [--clip-frames <dir>] [--clip-scene ui-demo]
//           [--clip-fps 30] [--clip-lead 0.4]
// Captures one PNG per frame and writes a ffmpeg concat file.
// When --clip-frames is given, frames extracted from the recorded GUI demo
// clip (clip-%04d.png) are injected into the named scene's #live-demo-frame
// <img> element, one clip frame per output frame.

const { chromium } = require("playwright");
const fs = require("fs");
const path = require("path");

function arg(name, fallback) {
  const i = process.argv.indexOf(name);
  return i === -1 ? fallback : process.argv[i + 1];
}

const htmlPath = path.resolve(process.argv[2]);
const framesDir = path.resolve(process.argv[3]);
const fps = parseInt(arg("--fps", "30"), 10);
const width = parseInt(arg("--width", "1920"), 10);
const height = parseInt(arg("--height", "1080"), 10);
const clipFramesDir = arg("--clip-frames", null);
const clipSceneId = arg("--clip-scene", "ui-demo");
const clipFps = parseInt(arg("--clip-fps", "30"), 10);
const clipLead = parseFloat(arg("--clip-lead", "0.4"));

(async () => {
  fs.mkdirSync(framesDir, { recursive: true });

  let clipFrames = [];
  if (clipFramesDir) {
    clipFrames = fs
      .readdirSync(clipFramesDir)
      .filter((f) => /^clip-\d+\.png$/i.test(f))
      .sort();
    if (clipFrames.length === 0) {
      throw new Error(`No clip frames in ${clipFramesDir}`);
    }
  }

  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width, height } });
  await page.goto(`file:///${htmlPath.replace(/\\/g, "/")}`);
  await page.waitForFunction(() => typeof window.__totalDuration === "function");

  const total = await page.evaluate(() => window.__totalDuration());
  const scenes = await page.evaluate(() => window.__SCENES__);
  const frameCount = Math.ceil(total * fps);
  console.log(
    JSON.stringify({ total, fps, frameCount, width, height, clipFrames: clipFrames.length })
  );

  // Locate the clip scene's time window.
  let clipStart = null;
  let clipEnd = null;
  if (clipFrames.length > 0) {
    let cursor = 0;
    for (const scene of scenes) {
      if (scene.id === clipSceneId) {
        clipStart = cursor;
        clipEnd = cursor + scene.duration;
        break;
      }
      cursor += scene.duration;
    }
    if (clipStart === null) {
      throw new Error(`Scene ${clipSceneId} not found in storyboard`);
    }
  }

  const concatLines = [];
  const frameDuration = 1 / fps;

  // Cache clip frames as data URLs up front: the scene renderer wipes the
  // DOM on every seek, so the <img> must be re-populated every single frame.
  const clipDataUrls = clipFrames.map((f) => {
    const png = fs.readFileSync(path.join(clipFramesDir, f));
    return `data:image/png;base64,${png.toString("base64")}`;
  });

  for (let i = 0; i < frameCount; i++) {
    const t = i * frameDuration;
    await page.evaluate((s) => window.__seek(s), t);

    if (clipStart !== null && t >= clipStart && t < clipEnd) {
      const clipTime = t - clipStart - clipLead;
      const clipIndex = Math.max(
        0,
        Math.min(clipFrames.length - 1, Math.floor(clipTime * clipFps))
      );
      await page.evaluate((src) => {
        const img = document.getElementById("live-demo-frame");
        if (img) img.src = src;
      }, clipDataUrls[clipIndex]);
      await page.evaluate(() => {
        const img = document.getElementById("live-demo-frame");
        return img && img.decode ? img.decode().catch(() => {}) : null;
      });
    }

    const name = `frame-${String(i).padStart(5, "0")}.png`;
    const file = path.join(framesDir, name);
    await page.screenshot({ path: file, type: "png" });
    concatLines.push(`file '${name}'`);
    concatLines.push(`duration ${frameDuration.toFixed(6)}`);
    if (i % 60 === 0) {
      process.stdout.write(`\rframe ${i}/${frameCount}`);
    }
  }
  // concat demuxer needs the last file repeated without a duration line.
  const lastName = `frame-${String(frameCount - 1).padStart(5, "0")}.png`;
  concatLines.push(`file '${lastName}'`);

  fs.writeFileSync(
    path.join(framesDir, "concat.txt"),
    concatLines.join("\n") + "\n",
    "utf8"
  );

  await browser.close();
  console.log(`\nDone. ${frameCount} frames -> ${framesDir}`);
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
