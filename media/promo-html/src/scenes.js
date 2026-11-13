// Scene timing and ordering. The recorder reads this through window.__SCENES__.
window.__SCENES__ = [
  {
    id: "hook",
    duration: 4.5,
    narration: "同一台笔记本，插电和用电池的时候，性能和续航差别往往很大。",
  },
  {
    id: "problem",
    duration: 5.5,
    narration: "插电想要性能，选四十五瓦；嫌风扇吵想要安静，选二十五瓦；只用电池时二十五瓦够用，想更久续航就选十瓦。",
  },
  {
    id: "ui-demo",
    duration: 11.0,
    narration: "三个按钮，点一下立刻切换。现在用了多少瓦、温度多少、上限多少，都实时显示在界面上。",
  },
  {
    id: "auto-policy",
    duration: 6.0,
    narration: "嫌手动切换麻烦，可以打开自动策略：插上电源自动切到高性能，拔掉电源自动切到省电。",
  },
  {
    id: "safety",
    duration: 5.5,
    narration: "默认只能看，不能改，不怕点错。想修改时点右上角的锁，读完须知、勾选同意才生效。",
  },
  {
    id: "compat",
    duration: 5.0,
    narration: "已经实测过的型号可以直接用，其他 AMD 型号会先做安全检测，再决定能不能修改。",
  },
  {
    id: "closing",
    duration: 5.0,
    narration: "项目完全开源免费，欢迎去 GitHub 下载试用，也欢迎告诉我们你的机型。",
  },
];
