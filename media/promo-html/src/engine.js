// AMD Mobile Power promo engine.
// Exposes window.__seek(seconds) and window.__totalDuration() so the
// Playwright recorder can drive frame-exact captures.

const SCENE_DEFS = window.__SCENES__ || [];
const FPS = 30;

function buildTimeline(scenes) {
  let t = 0;
  return scenes.map((scene) => {
    const start = t;
    const end = t + scene.duration;
    t = end;
    return { ...scene, start, end };
  });
}

const timeline = buildTimeline(SCENE_DEFS);
const TOTAL = TOTAL_DURATION();

function TOTAL_DURATION() {
  return timeline.length ? timeline[timeline.length - 1].end : 0;
}

function clamp01(v) {
  return Math.max(0, Math.min(1, v));
}

function easeInOut(t) {
  return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t;
}
function easeOut(t) {
  return 1 - Math.pow(1 - t, 3);
}
function easeIn(t) {
  return t * t * t;
}

function sceneAt(time) {
  for (const scene of timeline) {
    if (time >= scene.start && time < scene.end) return scene;
  }
  return timeline[timeline.length - 1];
}

function renderScene(scene, localTime, root) {
  const renderer = SCENE_RENDERERS[scene.id];
  if (renderer) renderer(scene, localTime, root);
  if (scene.narration) drawCaption(scene, localTime, root);
}

// Burned-in subtitle band: the video has no voice track, so the narration
// text carries the story. Fades in shortly after the scene cut and out
// before the next one.
function drawCaption(scene, t, root) {
  const fadeIn = clamp01((t - 0.45) / 0.35);
  const fadeOut = clamp01((scene.duration - 0.35 - t) / 0.35);
  const fade = Math.min(fadeIn, fadeOut);
  if (fade <= 0) return;
  const band = el("div", {
    position: "absolute", left: "0", right: "0", bottom: "0",
    padding: "34px 120px 36px", display: "flex", justifyContent: "center",
    background:
      "linear-gradient(180deg, rgba(8,14,17,0) 0%, rgba(8,14,17,0.78) 45%, rgba(8,14,17,0.88) 100%)",
    opacity: String(fade),
  });
  const text = txt(scene.narration, {
    color: "#e8f0ec", fontSize: "31px", fontWeight: "500",
    fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
    letterSpacing: "0.5px", textAlign: "center", lineHeight: "1.55",
    maxWidth: "1620px",
  });
  band.append(text);
  root.append(band);
}

const SCENE_RENDERERS = {};

function el(tag, style, children) {
  const node = document.createElement(tag);
  if (style) Object.assign(node.style, style);
  if (children) node.append(...children);
  return node;
}

function txt(content, style) {
  const node = document.createElement("div");
  node.textContent = content;
  if (style) Object.assign(node.style, style);
  return node;
}

function fadeSlide(scene, localTime, inDur = 0.45, outDur = 0.45) {
  const inA = clamp01(localTime / inDur);
  const outA = clamp01((scene.duration - localTime) / outDur);
  return Math.min(inA, outA);
}

function slideUp(node, localTime, delay, dist = 40) {
  const t = clamp01((localTime - delay) / 0.55);
  const eased = easeOut(t);
  node.style.opacity = String(eased);
  node.style.transform = `translateY(${(1 - eased) * dist}px)`;
}

SCENE_RENDERERS.hook = (scene, t, root) => {
  root.innerHTML = "";
  const opacity = fadeSlide(scene, t);
  const wrap = el("div", {
    position: "absolute", inset: "0", opacity: String(opacity),
    display: "flex", alignItems: "center",
    padding: "0 100px 0 120px",
    background: "linear-gradient(160deg,#0b1216 0%,#0d1a1c 55%,#0a1a14 100%)",
  });

  const left = el("div", {
    display: "flex", flexDirection: "column", justifyContent: "center",
    width: "1150px", flexShrink: "0",
  });

  const eyebrow = txt("给 AMD 笔记本的功耗开关", {
    color: "#45d6a8", fontSize: "26px", fontWeight: "700",
    letterSpacing: "6px", marginBottom: "28px",
    fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
  });
  slideUp(eyebrow, t, 0.1);

  const title = el("div", {});
  title.innerHTML = "想快就快<br>想省就省";
  Object.assign(title.style, {
    color: "#f1f7f4", fontSize: "118px", fontWeight: "900", lineHeight: "1.1",
    fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
    letterSpacing: "0px", marginBottom: "32px",
  });
  slideUp(title, t, 0.22);

  const sub = txt("AMD 笔记本 · 功耗开关 · 插电电池一键切换", {
    color: "#a6b8b0", fontSize: "34px", fontWeight: "400",
    fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
  });
  slideUp(sub, t, 0.38);

  const bar = el("div", {
    position: "absolute", left: "120px", top: "120px",
    width: "64px", height: "6px", background: "#45d6a8", borderRadius: "3px",
  });
  slideUp(bar, t, 0.0);

  // Brand icon on the right with a soft accent ring.
  const iconWrap = el("div", {
    flex: "1", display: "flex", alignItems: "center", justifyContent: "center",
  });
  const ring = el("div", {
    width: "380px", height: "380px", borderRadius: "50%",
    border: "2px solid rgba(69,214,168,0.35)",
    boxShadow: "0 0 90px rgba(69,214,168,0.18), inset 0 0 60px rgba(69,214,168,0.08)",
    display: "flex", alignItems: "center", justifyContent: "center",
  });
  const icon = el("img", { width: "220px", height: "220px" });
  icon.src = "../../assets/amd-mobile-power-256.png";
  ring.append(icon);
  iconWrap.append(ring);
  const ringPop = clamp01((t - 0.45) / 0.6);
  const ringEased = easeOut(ringPop);
  iconWrap.style.opacity = String(ringEased);
  iconWrap.style.transform = `scale(${0.85 + 0.15 * ringEased})`;

  left.append(eyebrow, title, sub);
  wrap.append(bar, left, iconWrap);
  root.append(wrap);
};

SCENE_RENDERERS.problem = (scene, t, root) => {
  root.innerHTML = "";
  const opacity = fadeSlide(scene, t);
  const wrap = el("div", {
    position: "absolute", inset: "0", opacity: String(opacity),
    display: "flex", flexDirection: "column", justifyContent: "center",
    padding: "0 120px", background: "linear-gradient(180deg,#0b1216 0%,#0c1418 100%)",
  });

  const eyebrow = txt("三种场景 三种功率", {
    color: "#45d6a8", fontSize: "24px", fontWeight: "700",
    letterSpacing: "6px", marginBottom: "32px",
  });
  slideUp(eyebrow, t, 0.05);

  const title = el("div", {});
  title.innerHTML = "按需选瓦数<br>各有各的爽";
  Object.assign(title.style, {
    color: "#f1f7f4", fontSize: "96px", fontWeight: "900", lineHeight: "1.1",
    fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
    marginBottom: "56px",
  });
  slideUp(title, t, 0.18);

  const cards = [
    { label: "插电 · 性能", value: "45 W", hint: "畅玩 · 剪辑", tone: "#45d6a8", delay: 0.5 },
    { label: "安静 · 办公", value: "25 W", hint: "风扇更安静", tone: "#ffb45a", delay: 0.68 },
    { label: "电池 · 长续航", value: "10 W", hint: "撑得更久", tone: "#7fb2ff", delay: 0.86 },
  ];
  const row = el("div", { display: "flex", gap: "36px" });
  for (const card of cards) {
    const box = el("div", {
      flex: "1", background: "rgba(255,255,255,0.04)",
      border: "1px solid rgba(255,255,255,0.08)", borderRadius: "12px",
      padding: "40px 40px 34px", display: "flex", flexDirection: "column", gap: "14px",
    });
    const label = txt(card.label, {
      color: "#a6b8b0", fontSize: "26px", fontWeight: "500",
      fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
    });
    const value = txt(card.value, {
      color: card.tone, fontSize: "72px", fontWeight: "900",
      fontFamily: "'Segoe UI',sans-serif", letterSpacing: "-1px",
    });
    const hint = txt(card.hint, {
      color: "#7d8f88", fontSize: "24px", fontWeight: "400",
      fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
    });
    box.append(label, value, hint);
    slideUp(box, t, card.delay);
    row.append(box);
  }

  wrap.append(eyebrow, title, row);
  root.append(wrap);
};

SCENE_RENDERERS["ui-demo"] = (scene, t, root) => {
  root.innerHTML = "";
  const opacity = fadeSlide(scene, t, 0.35, 0.35);
  const wrap = el("div", {
    position: "absolute", inset: "0", opacity: String(opacity),
    background: "linear-gradient(180deg,#0b1216 0%,#0c1418 100%)",
    display: "flex", alignItems: "center", padding: "0 90px 0 110px", gap: "70px",
  });

  const head = el("div", {
    display: "flex", flexDirection: "column", width: "520px", flexShrink: "0",
  });
  const eyebrow = txt("ONE-CLICK PRESETS", {
    color: "#45d6a8", fontSize: "22px", fontWeight: "700",
    letterSpacing: "5px", marginBottom: "20px",
  });
  const title = el("div", {});
  title.innerHTML = "一键切换<br>三档功耗";
  Object.assign(title.style, {
    color: "#f1f7f4", fontSize: "72px", fontWeight: "900", lineHeight: "1.12",
    fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
    marginBottom: "28px",
  });
  const sub = txt("当前功耗 · 温度 · 上限 实时可见", {
    color: "#a6b8b0", fontSize: "26px",
    fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
  });
  head.append(eyebrow, title, sub);
  slideUp(head, t, 0.1);

  // The demo clip is 1200x720 (5:3); the right column holds it at 1050x630.
  const frameWrap = el("div", {
    width: "1050px", height: "630px", flexShrink: "0",
    position: "relative", borderRadius: "14px", overflow: "hidden",
    border: "1px solid rgba(69,214,168,0.25)",
    boxShadow: "0 24px 64px rgba(0,0,0,0.5)", background: "#10181d",
  });
  const img = el("img", {
    width: "100%", height: "100%", objectFit: "contain", display: "block",
  });
  img.id = "live-demo-frame";
  img.src = window.__CLIP_POSTER__ || "";
  frameWrap.append(img);

  const framePop = clamp01((t - 0.15) / 0.5);
  const frameEased = easeOut(framePop);
  frameWrap.style.opacity = String(frameEased);
  frameWrap.style.transform = `translateY(${(1 - frameEased) * 30}px)`;

  wrap.append(head, frameWrap);
  root.append(wrap);
};

SCENE_RENDERERS.safety = (scene, t, root) => {
  root.innerHTML = "";
  const opacity = fadeSlide(scene, t);
  const wrap = el("div", {
    position: "absolute", inset: "0", opacity: String(opacity),
    display: "flex", alignItems: "center",
    padding: "0 110px 0 120px", gap: "80px",
    background: "linear-gradient(180deg,#0b1216 0%,#0c1418 100%)",
  });

  const left = el("div", {
    display: "flex", flexDirection: "column", justifyContent: "center",
    width: "1050px", flexShrink: "0",
  });

  const eyebrow = txt("安全第一", {
    color: "#45d6a8", fontSize: "24px", fontWeight: "700",
    letterSpacing: "6px", marginBottom: "32px",
  });
  slideUp(eyebrow, t, 0.05);

  const title = el("div", {});
  title.innerHTML = "默认只读<br>不怕点错";
  Object.assign(title.style, {
    color: "#f1f7f4", fontSize: "88px", fontWeight: "900", lineHeight: "1.1",
    fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
    marginBottom: "48px",
  });
  slideUp(title, t, 0.18);

  const items = [
    ["只看不改", "默认什么都不会动"],
    ["自动核对", "改完立刻检查是否生效"],
    ["说清楚", "没生效会直接提示"],
  ];
  const list = el("div", { display: "flex", flexDirection: "column", gap: "20px" });
  items.forEach(([head, body], i) => {
    const row = el("div", { display: "flex", alignItems: "baseline", gap: "24px" });
    const dot = el("div", {
      width: "10px", height: "10px", borderRadius: "50%",
      background: "#45d6a8", flexShrink: "0", transform: "translateY(-4px)",
    });
    const content = el("div", {
      display: "flex", alignItems: "baseline", gap: "20px", flexWrap: "wrap",
    });
    const h = txt(head, {
      color: "#f1f7f4", fontSize: "38px", fontWeight: "700",
      fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
    });
    const b = txt(body, {
      color: "#a6b8b0", fontSize: "28px", fontWeight: "400",
      fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
    });
    content.append(h, b);
    row.append(dot, content);
    slideUp(row, t, 0.35 + i * 0.18);
    list.append(row);
  });

  // Right: mock write-gate card (read-only by default, explicit unlock).
  const card = el("div", {
    flex: "1", background: "rgba(255,255,255,0.04)",
    border: "1px solid rgba(255,255,255,0.1)", borderRadius: "14px",
    padding: "44px 42px", display: "flex", flexDirection: "column", gap: "26px",
  });
  const cardHead = txt("修改开关", {
    color: "#f1f7f4", fontSize: "28px", fontWeight: "700",
    fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
  });
  const toggleRow = el("div", {
    display: "flex", alignItems: "center", justifyContent: "space-between",
  });
  const toggleLabel = txt("只看不改 · 默认状态", {
    color: "#a6b8b0", fontSize: "24px",
    fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
  });
  const toggle = el("div", {
    width: "64px", height: "34px", borderRadius: "17px",
    background: "rgba(255,255,255,0.14)", position: "relative",
  });
  const knob = el("div", {
    width: "26px", height: "26px", borderRadius: "50%",
    background: "#f1f7f4", position: "absolute", left: "4px", top: "4px",
  });
  toggle.append(knob);
  toggleRow.append(toggleLabel, toggle);
  const divider = el("div", {
    height: "1px", background: "rgba(255,255,255,0.08)",
  });
  const checks = [
    "改完立刻检查是否生效",
    "同一时间只动一处",
    "没生效会直接说明",
  ];
  card.append(cardHead, toggleRow, divider);
  checks.forEach((c) => {
    const line = el("div", { display: "flex", gap: "14px", alignItems: "center" });
    const mark = txt("✓", {
      color: "#45d6a8", fontSize: "24px", fontWeight: "900",
    });
    const body = txt(c, {
      color: "#c9d6cf", fontSize: "22px",
      fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
    });
    line.append(mark, body);
    card.append(line);
  });
  const cardPop = clamp01((t - 0.5) / 0.6);
  const cardEased = easeOut(cardPop);
  card.style.opacity = String(cardEased);
  card.style.transform = `translateY(${(1 - cardEased) * 30}px)`;

  left.append(eyebrow, title, list);
  wrap.append(left, card);
  root.append(wrap);
};

SCENE_RENDERERS.compat = (scene, t, root) => {
  root.innerHTML = "";
  const opacity = fadeSlide(scene, t);
  const wrap = el("div", {
    position: "absolute", inset: "0", opacity: String(opacity),
    display: "flex", alignItems: "center",
    padding: "0 110px 0 120px", gap: "80px",
    background: "linear-gradient(180deg,#0b1216 0%,#0c1418 100%)",
  });

  const left = el("div", {
    display: "flex", flexDirection: "column", justifyContent: "center",
    width: "1050px", flexShrink: "0",
  });

  const eyebrow = txt("兼容性", {
    color: "#45d6a8", fontSize: "24px", fontWeight: "700",
    letterSpacing: "6px", marginBottom: "32px",
  });
  slideUp(eyebrow, t, 0.05);

  const title = el("div", {});
  title.innerHTML = "多种 AMD<br>轻薄本可用";
  Object.assign(title.style, {
    color: "#f1f7f4", fontSize: "88px", fontWeight: "900", lineHeight: "1.1",
    fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
    marginBottom: "48px",
  });
  slideUp(title, t, 0.18);

  const stats = [
    ["8845HS", "已实测可用"],
    ["其他型号", "先安全检测"],
    ["诊断", "一键导出"],
  ];
  const row = el("div", { display: "flex", gap: "36px" });
  stats.forEach(([num, label], i) => {
    const box = el("div", { flex: "1", display: "flex", flexDirection: "column", gap: "14px" });
    const n = txt(num, {
      color: "#45d6a8", fontSize: "56px", fontWeight: "900",
      fontFamily: "'Segoe UI',sans-serif", letterSpacing: "-1px",
    });
    const l = txt(label, {
      color: "#a6b8b0", fontSize: "24px",
      fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
    });
    box.append(n, l);
    slideUp(box, t, 0.4 + i * 0.16);
    row.append(box);
  });

  // Right: mock device card showing a verified platform.
  const card = el("div", {
    flex: "1", background: "rgba(255,255,255,0.04)",
    border: "1px solid rgba(255,255,255,0.1)", borderRadius: "14px",
    padding: "44px 42px", display: "flex", flexDirection: "column", gap: "20px",
  });
  const cardEyebrow = txt("已验证设备", {
    color: "#45d6a8", fontSize: "20px", fontWeight: "700", letterSpacing: "4px",
  });
  const cpu = txt("Ryzen 7 8845HS", {
    color: "#f1f7f4", fontSize: "42px", fontWeight: "900",
    fontFamily: "'Segoe UI',sans-serif",
  });
  const plat = txt("Hawk Point · Radeon 780M", {
    color: "#a6b8b0", fontSize: "24px",
    fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
  });
  const okRow = el("div", {
    display: "flex", alignItems: "center", gap: "12px", marginTop: "6px",
  });
  const okMark = txt("✓", { color: "#45d6a8", fontSize: "26px", fontWeight: "900" });
  const okText = txt("STAPM / Fast / Slow 全部可写", {
    color: "#c9d6cf", fontSize: "22px",
    fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
  });
  okRow.append(okMark, okText);
  const noteRow = txt("其他世代 → 保守 profile 只读兜底", {
    color: "#a6b8b0", fontSize: "20px",
    fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
  });
  card.append(cardEyebrow, cpu, plat, okRow, noteRow);
  const cardPop = clamp01((t - 0.5) / 0.6);
  const cardEased = easeOut(cardPop);
  card.style.opacity = String(cardEased);
  card.style.transform = `translateY(${(1 - cardEased) * 30}px)`;

  left.append(eyebrow, title, row);
  wrap.append(left, card);
  root.append(wrap);
};

SCENE_RENDERERS["auto-policy"] = (scene, t, root) => {
  root.innerHTML = "";
  const opacity = fadeSlide(scene, t);
  const wrap = el("div", {
    position: "absolute", inset: "0", opacity: String(opacity),
    display: "flex", alignItems: "center",
    padding: "0 110px 0 120px", gap: "90px",
    background: "linear-gradient(180deg,#0b1216 0%,#0c1418 100%)",
  });

  const left = el("div", {
    display: "flex", flexDirection: "column", justifyContent: "center",
    width: "980px", flexShrink: "0",
  });

  const eyebrow = txt("全自动", {
    color: "#45d6a8", fontSize: "24px", fontWeight: "700",
    letterSpacing: "6px", marginBottom: "32px",
  });
  slideUp(eyebrow, t, 0.05);

  const title = el("div", {});
  title.innerHTML = "也可以<br>全自动";
  Object.assign(title.style, {
    color: "#f1f7f4", fontSize: "96px", fontWeight: "900", lineHeight: "1.1",
    fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
    marginBottom: "40px",
  });
  slideUp(title, t, 0.18);

  const sub = txt("设置一次，之后按电源状态自动切换", {
    color: "#a6b8b0", fontSize: "28px",
    fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
  });
  slideUp(sub, t, 0.34);

  // Right: auto-policy card with an enabled toggle and two mapping rows.
  const card = el("div", {
    flex: "1", background: "rgba(255,255,255,0.04)",
    border: "1px solid rgba(255,255,255,0.1)", borderRadius: "14px",
    padding: "42px 44px", display: "flex", flexDirection: "column", gap: "26px",
  });
  const headRow = el("div", {
    display: "flex", alignItems: "center", justifyContent: "space-between",
  });
  const headTitle = txt("自动电源策略", {
    color: "#f1f7f4", fontSize: "28px", fontWeight: "700",
    fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
  });
  const toggle = el("div", {
    width: "72px", height: "38px", borderRadius: "19px",
    background: "#45d6a8", position: "relative",
  });
  const knob = el("div", {
    width: "30px", height: "30px", borderRadius: "50%",
    background: "#0b1216", position: "absolute", right: "4px", top: "4px",
  });
  toggle.append(knob);
  headRow.append(headTitle, toggle);

  const divider = el("div", { height: "1px", background: "rgba(255,255,255,0.08)" });

  const mkRow = (chip, chipColor, value) => {
    const row = el("div", {
      display: "flex", alignItems: "center", gap: "24px",
    });
    const tag = txt(chip, {
      background: `${chipColor}22`, border: `1px solid ${chipColor}66`,
      color: chipColor, fontSize: "24px", fontWeight: "700",
      padding: "10px 22px", borderRadius: "10px",
      fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
    });
    const arrow = txt("→", {
      color: "#7d8f88", fontSize: "30px", fontWeight: "400",
    });
    const val = txt(`自动 ${value}`, {
      color: "#f1f7f4", fontSize: "38px", fontWeight: "900",
      fontFamily: "'Segoe UI',sans-serif",
    });
    row.append(tag, arrow, val);
    return row;
  };
  const rowAc = mkRow("插上电源", "#45d6a8", "45 W");
  const rowBattery = mkRow("电池供电", "#ffb45a", "10 W");
  slideUp(rowAc, t, 0.5);
  slideUp(rowBattery, t, 0.68);

  const hint = txt("拔掉电源 → 自动省电   插上电源 → 自动满血", {
    color: "#7d8f88", fontSize: "22px",
    fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
  });
  slideUp(hint, t, 0.86);

  card.append(headRow, divider, rowAc, rowBattery, hint);
  const cardPop = clamp01((t - 0.35) / 0.6);
  const cardEased = easeOut(cardPop);
  card.style.opacity = String(cardEased);
  card.style.transform = `translateY(${(1 - cardEased) * 30}px)`;

  left.append(eyebrow, title, sub);
  wrap.append(left, card);
  root.append(wrap);
};

SCENE_RENDERERS.closing = (scene, t, root) => {
  root.innerHTML = "";
  const opacity = fadeSlide(scene, t, 0.4, 0.6);
  const wrap = el("div", {
    position: "absolute", inset: "0", opacity: String(opacity),
    display: "flex", flexDirection: "column", justifyContent: "center",
    alignItems: "center", padding: "0 120px",
    background: "linear-gradient(160deg,#0b1216 0%,#0a1a14 100%)",
    textAlign: "center",
  });

  const eyebrow = txt("开源 · 免费", {
    color: "#45d6a8", fontSize: "24px", fontWeight: "700",
    letterSpacing: "6px", marginBottom: "32px",
  });
  slideUp(eyebrow, t, 0.05);

  const title = el("div", {});
  title.innerHTML = "欢迎试用<br>欢迎反馈";
  Object.assign(title.style, {
    color: "#f1f7f4", fontSize: "108px", fontWeight: "900", lineHeight: "1.1",
    fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
    marginBottom: "36px",
  });
  slideUp(title, t, 0.2);

  const repo = txt("github.com/syttys123/amd-mobile-power", {
    color: "#45d6a8", fontSize: "32px", fontWeight: "600",
    fontFamily: "'Segoe UI',sans-serif", marginBottom: "20px",
  });
  slideUp(repo, t, 0.38);

  const note = txt(
    "开源免费 · 下载即用 · 欢迎告诉我们你的机型", {
    color: "#a6b8b0", fontSize: "24px",
    fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
  });
  slideUp(note, t, 0.5);

  wrap.append(eyebrow, title, repo, note);
  root.append(wrap);
};

window.__totalDuration = () => TOTAL_DURATION();
window.__seek = (seconds) => {
  const root = document.getElementById("root");
  if (!root) return;
  const scene = sceneAt(seconds);
  const localTime = seconds - scene.start;
  renderScene(scene, localTime, root);
};

window.__seek(0);
