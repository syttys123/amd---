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
  if (!renderer) return;
  renderer(scene, localTime, root);
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
    display: "flex", flexDirection: "column", justifyContent: "center",
    padding: "0 120px",
    background: "linear-gradient(160deg,#0b1216 0%,#0d1a1c 55%,#0a1a14 100%)",
  });

  const eyebrow = txt("OPEN SOURCE · NATIVE WINDOWS APP", {
    color: "#45d6a8", fontSize: "26px", fontWeight: "700",
    letterSpacing: "6px", marginBottom: "28px", fontFamily: "'Segoe UI',sans-serif",
  });
  slideUp(eyebrow, t, 0.1);

  const title = el("div", {});
  title.innerHTML = "AMD 轻薄本<br>功耗一手掌握";
  Object.assign(title.style, {
    color: "#f1f7f4", fontSize: "118px", fontWeight: "900", lineHeight: "1.08",
    fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
    letterSpacing: "-1px", marginBottom: "32px",
  });
  slideUp(title, t, 0.22);

  const sub = txt("原生 GUI · 实时回读 · 三档预设 · 开源", {
    color: "#a6b8b0", fontSize: "34px", fontWeight: "400",
    fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
  });
  slideUp(sub, t, 0.38);

  const bar = el("div", {
    position: "absolute", left: "120px", top: "120px",
    width: "64px", height: "6px", background: "#45d6a8", borderRadius: "3px",
  });
  slideUp(bar, t, 0.0);

  wrap.append(bar, eyebrow, title, sub);
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

  const eyebrow = txt("THE PROBLEM", {
    color: "#45d6a8", fontSize: "24px", fontWeight: "700",
    letterSpacing: "6px", marginBottom: "32px",
  });
  slideUp(eyebrow, t, 0.05);

  const title = el("div", {});
  title.innerHTML = "同一台电脑<br>三种功耗性格";
  Object.assign(title.style, {
    color: "#f1f7f4", fontSize: "96px", fontWeight: "900", lineHeight: "1.1",
    fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
    marginBottom: "56px",
  });
  slideUp(title, t, 0.18);

  const cards = [
    { label: "插电", value: "45 W", tone: "#45d6a8", delay: 0.5 },
    { label: "电池", value: "25 W", tone: "#ffb45a", delay: 0.68 },
    { label: "充电宝", value: "???", tone: "#e06c6c", delay: 0.86 },
  ];
  const row = el("div", { display: "flex", gap: "36px" });
  for (const card of cards) {
    const box = el("div", {
      flex: "1", background: "rgba(255,255,255,0.04)",
      border: "1px solid rgba(255,255,255,0.08)", borderRadius: "12px",
      padding: "44px 40px", display: "flex", flexDirection: "column", gap: "18px",
    });
    const label = txt(card.label, {
      color: "#a6b8b0", fontSize: "26px", fontWeight: "500",
      fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
    });
    const value = txt(card.value, {
      color: card.tone, fontSize: "72px", fontWeight: "900",
      fontFamily: "'Segoe UI',sans-serif", letterSpacing: "-1px",
    });
    box.append(label, value);
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
    display: "flex", flexDirection: "column", padding: "80px 100px 60px",
  });

  const head = el("div", {
    display: "flex", justifyContent: "space-between",
    alignItems: "flex-end", marginBottom: "36px",
  });
  const eyebrow = txt("ONE-CLICK PRESETS", {
    color: "#45d6a8", fontSize: "22px", fontWeight: "700",
    letterSpacing: "5px", marginBottom: "12px",
  });
  const title = el("div", {});
  title.innerHTML = "一键切换<br>三档功耗";
  Object.assign(title.style, {
    color: "#f1f7f4", fontSize: "76px", fontWeight: "900", lineHeight: "1.1",
    fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
  });
  const headLeft = el("div", {});
  headLeft.append(eyebrow, title);
  head.append(headLeft);
  slideUp(head, t, 0.1);

  const frameWrap = el("div", {
    flex: "1", position: "relative", borderRadius: "14px", overflow: "hidden",
    border: "1px solid rgba(69,214,168,0.25)",
    boxShadow: "0 24px 64px rgba(0,0,0,0.5)",
  });
  const img = el("img", {
    width: "100%", height: "100%", objectFit: "cover", display: "block",
  });
  img.id = "live-demo-frame";
  img.src = window.__CLIP_POSTER__ || "";
  frameWrap.append(img);

  const chips = el("div", {
    position: "absolute", left: "40px", bottom: "40px",
    display: "flex", gap: "16px",
  });
  const chipData = [
    { label: "10 W · 夜间电池" },
    { label: "25 W · 日常插电" },
    { label: "45 W · 性能模式" },
  ];
  const chipNodes = chipData.map((c) => txt(c.label, {
    background: "rgba(0,0,0,0.55)", backdropFilter: "blur(8px)",
    color: "#a6b8b0", fontSize: "22px", fontWeight: "600",
    padding: "12px 22px", borderRadius: "8px",
    border: "1px solid rgba(255,255,255,0.12)",
    fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
  }));
  chips.append(...chipNodes);
  frameWrap.append(chips);

  // The recorder maps localTime -> clipTime -> active chip.
  const clipTime = Math.max(0, t - 0.4);
  let active = 0;
  if (clipTime >= 7.6) active = 0;
  else if (clipTime >= 4.6) active = 2;
  else if (clipTime >= 1.6) active = 1;
  chipNodes.forEach((chip, i) => {
    const on = i === active && clipTime > 0.5;
    chip.style.color = on ? "#0b1216" : "#a6b8b0";
    chip.style.background = on ? "#45d6a8" : "rgba(0,0,0,0.55)";
    chip.style.borderColor = on ? "#45d6a8" : "rgba(255,255,255,0.12)";
  });

  wrap.append(head, frameWrap);
  root.append(wrap);
};

SCENE_RENDERERS.safety = (scene, t, root) => {
  root.innerHTML = "";
  const opacity = fadeSlide(scene, t);
  const wrap = el("div", {
    position: "absolute", inset: "0", opacity: String(opacity),
    display: "flex", flexDirection: "column", justifyContent: "center",
    padding: "0 120px", background: "linear-gradient(180deg,#0b1216 0%,#0c1418 100%)",
  });

  const eyebrow = txt("FAIL CLOSED BY DESIGN", {
    color: "#45d6a8", fontSize: "24px", fontWeight: "700",
    letterSpacing: "6px", marginBottom: "32px",
  });
  slideUp(eyebrow, t, 0.05);

  const title = el("div", {});
  title.innerHTML = "默认只读<br>写入必回读";
  Object.assign(title.style, {
    color: "#f1f7f4", fontSize: "96px", fontWeight: "900", lineHeight: "1.1",
    fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
    marginBottom: "56px",
  });
  slideUp(title, t, 0.18);

  const items = [
    ["默认只读", "不申请写入权限也能看功耗"],
    ["worker 隔离", "硬件访问独立进程，单所有者"],
    ["回读确认", "固件钳制直接提示，不静默跳过"],
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

  wrap.append(eyebrow, title, list);
  root.append(wrap);
};

SCENE_RENDERERS.compat = (scene, t, root) => {
  root.innerHTML = "";
  const opacity = fadeSlide(scene, t);
  const wrap = el("div", {
    position: "absolute", inset: "0", opacity: String(opacity),
    display: "flex", flexDirection: "column", justifyContent: "center",
    padding: "0 120px", background: "linear-gradient(180deg,#0b1216 0%,#0c1418 100%)",
  });

  const eyebrow = txt("EVIDENCE FIRST", {
    color: "#45d6a8", fontSize: "24px", fontWeight: "700",
    letterSpacing: "6px", marginBottom: "32px",
  });
  slideUp(eyebrow, t, 0.05);

  const title = el("div", {});
  title.innerHTML = "多世代探测<br>证据优先";
  Object.assign(title.style, {
    color: "#f1f7f4", fontSize: "96px", fontWeight: "900", lineHeight: "1.1",
    fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
    marginBottom: "56px",
  });
  slideUp(title, t, 0.18);

  const stats = [
    ["8845HS", "已实机验证"],
    ["多世代", "保守 profile 兜底"],
    ["脱敏诊断", "只读收集，可脱敏"],
  ];
  const row = el("div", { display: "flex", gap: "40px" });
  stats.forEach(([num, label], i) => {
    const box = el("div", { flex: "1", display: "flex", flexDirection: "column", gap: "14px" });
    const n = txt(num, {
      color: "#45d6a8", fontSize: "64px", fontWeight: "900",
      fontFamily: "'Segoe UI',sans-serif", letterSpacing: "-1px",
    });
    const l = txt(label, {
      color: "#a6b8b0", fontSize: "26px",
      fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
    });
    box.append(n, l);
    slideUp(box, t, 0.4 + i * 0.16);
    row.append(box);
  });

  wrap.append(eyebrow, title, row);
  root.append(wrap);
};

SCENE_RENDERERS.a11y = (scene, t, root) => {
  root.innerHTML = "";
  const opacity = fadeSlide(scene, t);
  const wrap = el("div", {
    position: "absolute", inset: "0", opacity: String(opacity),
    display: "flex", flexDirection: "column", justifyContent: "center",
    padding: "0 120px", background: "linear-gradient(180deg,#0b1216 0%,#0c1418 100%)",
  });

  const eyebrow = txt("ACCESSIBILITY", {
    color: "#45d6a8", fontSize: "24px", fontWeight: "700",
    letterSpacing: "6px", marginBottom: "32px",
  });
  slideUp(eyebrow, t, 0.05);

  const title = el("div", {});
  title.innerHTML = "高对比度<br>小窗也能读";
  Object.assign(title.style, {
    color: "#f1f7f4", fontSize: "96px", fontWeight: "900", lineHeight: "1.1",
    fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
    marginBottom: "48px",
  });
  slideUp(title, t, 0.18);

  const pills = [
    "跟随 Windows 高对比度",
    "1366×768 / 200% 可滚动",
    "DPI 切换保留窗口状态",
  ];
  const row = el("div", { display: "flex", gap: "16px", flexWrap: "wrap" });
  pills.forEach((p, i) => {
    const pill = txt(p, {
      border: "1px solid rgba(69,214,168,0.4)", color: "#45d6a8",
      fontSize: "24px", fontWeight: "600", padding: "14px 26px",
      borderRadius: "999px",
      fontFamily: "'Microsoft YaHei UI','Segoe UI',sans-serif",
    });
    slideUp(pill, t, 0.42 + i * 0.14);
    row.append(pill);
  });

  wrap.append(eyebrow, title, row);
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

  const eyebrow = txt("OPEN SOURCE · SAFETY FIRST", {
    color: "#45d6a8", fontSize: "24px", fontWeight: "700",
    letterSpacing: "6px", marginBottom: "32px",
  });
  slideUp(eyebrow, t, 0.05);

  const title = el("div", {});
  title.innerHTML = "谨慎折腾<br>欢迎共建";
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
    "提交 issue 前请附上脱敏诊断 · 折腾硬件有风险，请从保守数值开始", {
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
