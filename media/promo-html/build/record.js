// Frame-exact Playwright recorder for the promo HTML timeline.
// Usage:
//   node record.js <html-path> <frames-dir> [--fps 30] [--width 1920] [--height 1080]
// Captures one PNG per frame and writes a ffmpeg concat file.

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

(async () => {
  fs.mkdirSync(framesDir, { recursive: true });

  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width, height } });
  await page.goto(`file:///${htmlPath.replace(/\\/g, "/")}`);
  await page.waitForFunction(() => typeof window.__totalDuration === "function");

  const total = await page.evaluate(() => window.__totalDuration());
  const frameCount = Math.ceil(total * fps);
  console.log(
    JSON.stringify({ total, fps, frameCount, width, height })
  );

  const concatLines = [];
  const frameDuration = 1 / fps;

  for (let i = 0; i < frameCount; i++) {
    const t = i * frameDuration;
    await page.evaluate((s) => window.__seek(s), t);
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
