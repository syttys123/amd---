# AMD Mobile Power UI 设计数据库

最后更新：2026-11-10

## 1. 文档用途与证据边界

本文是 AMD Mobile Power 原生 WinForms UI 的维护入口。它把本机已有设计资料、
当前源码事实和本项目设计建议分开记录，避免把别家视觉语言直接当成实现方案。

本轮工作严格遵守以下边界：

- 未修改硬件，未启动或重启 GUI/worker，未控制鼠标键盘。
- 未修改 `MainForm`、主题辅助类或 worker。
- 未运行构建、测试、应用截图流程或会写缓存的工具。
- 唯一写入文件为本文。

注意：第 5 节保留 2026-11-10 改造前的源码基线；当前实现和验证证据见第 12 节。

证据标签：

| 标签 | 含义 |
| --- | --- |
| 本机资料事实 | 能在本机路径、清单、`package.json`、许可证或资料文件中直接核对 |
| 源码事实 | 能在当前工作树源码和行号中直接核对 |
| 设计建议 | 基于事实提出的本项目做法，尚未实施或运行验证 |
| 需运行时验证 | 静态发现的高风险点，必须由后续受控运行验证，本文不把它冒充已复现缺陷 |

## 2. 当前结论摘要

1. 简单模式当前采用 `560x400` 固定窗口、`132px` 左侧预设轨和约 `390px`
   主列。左轨把三个预设纵向堆叠，视觉权重过高，并压缩了功耗、目标和状态区域。
2. “当前预设”和“应用目标”同时使用实心强调色，形成两个主操作焦点；用户难以区分
   “当前状态”与“下一步动作”。
3. 指标值列约 `92px`，源码禁用自动省略；本机 `TextRenderer` 测量
   `105.0 / 105.0 °C` 约 `93px`，存在真实边界裁切风险。
4. 简单模式实际创建了一个新的 `_simpleWriteStateLabel`，但没有加入控件树；
   只读/写入锁定状态主要依赖禁用按钮，缺少持续可见的原因说明。
5. 建议删除左轨，改为单列四段式布局：
   `顶部实时值 + 目标行 -> 横向预设条 -> 四列遥测 -> 带原因的状态条`。
   这样能把主列从约 `390px` 扩展到 `536px`，同时保留四个遥测值。
6. 该四段式布局已于 2026-11-10 实现，并在 125% 缩放下完成窗口截图、
   UI Automation 和 OCR 验证。详见第 12 节。

## 3. 本机资料事实

### 3.1 搜索范围与结果

| 位置 | 本轮发现 | 结论 |
| --- | --- | --- |
| `D:\` 根目录及项目内 `node_modules` | `D:\tong\frontend\node_modules`、`D:\modular_mc_bot\node_modules` 等 | D 盘主要可复用 UI 证据来自桐前端依赖，不含完整大厂设计系统仓库 |
| `<local-design-library>\design-corpus` | 24 个官方组件库/设计系统仓库、Apple HIG、Atlassian 页面快照 | 本机最完整的 UI 设计资料库 |
| `<local-design-library>\ui-database` | SQLite 索引、token/component/principle 导出 | 设计资料的只读查询入口，不应在这里维护 AMD 项目结论 |
| `<USER_HOME>\Documents` | 未发现可用的组件库安装 | 本轮未发现可用的 UI 组件库安装 |
| `<USER_HOME>\AppData\Local\npm-cache` | `_npx` 下有 Playwright、Node、TypeScript、ESLint 等工具缓存 | 本轮未发现大厂设计系统安装 |

资料库自身说明：

- `<local-design-library>\design-corpus\README.md` 明确写明：24 个官方组件库或设计系统仓库，
  资料只用于研究和决策取证，代码复用前必须回到具体许可证文件。
- `<local-design-library>\ui-database\README.md` 明确写明：数据库是构建产物，原始证据仍在
  `design-corpus`，第三方代码复用不能只看汇总。
- 来源清单：`<local-design-library>\design-corpus\manifests\sources.md` 与
  `sources.json`，生成时间 `2026-11-07T09:09:02Z`。

### 3.2 本机官方设计系统仓库清单

路径均相对于 `<local-design-library>\design-corpus\repos`。提交号为清单记录，
`package.json` 版本为当前 checkout 的附加线索；工作组根包为 `0.0.0` 或私有包时，
不能把它误当成产品发布版本。

| 公司/系统 | 本地路径 | 版本或提交线索 | 许可证线索 |
| --- | --- | --- | --- |
| Google Material Web | `material-web` | `@material/web` 2.5.0；`d872455` | Apache-2.0，`LICENSE` |
| Google Material Components Web | `material-components-web` | `6ceadb8`；维护模式 | MIT，`LICENSE` |
| Microsoft Fluent UI | `fluentui` | 工作区 `1.0.0`；`19e2d5cd` | MIT，`LICENSE` |
| IBM Carbon | `carbon` | 工作区 `0.0.0`；`f5bdc21` | Apache-2.0，`LICENSE` |
| Adobe Spectrum CSS | `spectrum-css` | 工作区 `0.0.0`；`70d3660` | Apache-2.0，`LICENSE` |
| Adobe React Spectrum | `react-spectrum` | `2.21.0-beta.0`；无 Git 快照 | Apache-2.0，`LICENSE` |
| GitHub Primer React | `primer-react` | `35ff497` | MIT，`LICENSE` |
| GitHub Primer Design | `primer-design` | `1.0.0`；`87f799f` | MIT，`LICENSE` |
| Shopify Polaris | `polaris` | 工作区 `0.0.0`；`3f7954a` | MIT，`LICENSE.md` |
| Shopify Polaris React archive | `polaris-react-archive` | `3f7954a`；归档参考 | MIT，`LICENSE.md` |
| Ant Design | `ant-design` | `antd` 6.7.0；`92b0622` | MIT，`LICENSE` |
| ByteDance Arco Design | `arco-design` | `@arco-design/web-react` 2.66.18；`4e087a0` | MIT，`LICENSE` |
| ByteDance Semi Design | `semi-design` | 工作区 `0.0.1`；`b1cea33` | MIT，`LICENSE` |
| Tencent TDesign React | `tdesign-react` | 工作区无版本；`eb0081d` | MIT，`LICENSE` |
| Tencent TDesign Common | `tdesign-common` | `1.0.0`；`79d82e2` | MIT，`LICENSE` |
| Alibaba Fusion Design | `fusion-next` | 1.27.34；`d5582ba` | MIT，`LICENSE` |
| Salesforce Lightning Design System | `salesforce-design-system` | 2.28.1；`9bc6a40` | 需读取本地许可证，另有图标/图片条款 |
| Mozilla Protocol | `mozilla-protocol` | 22.0.0；`9107746` | MPL-2.0，`LICENSE` |
| Red Hat PatternFly | `patternfly` | `0.0.0-development`；`54e0888` | MIT，`LICENSE.txt` |
| Vaadin Web Components | `vaadin-components` | `dbf5eeb` | 稀疏快照未包含根许可证，复用前必须补齐 |
| Uber Base Web | `baseweb` | 18.2.0；`ed21081` | MIT，`LICENSE` |
| Pinterest Gestalt | `gestalt` | `7c1f32c` | Apache-2.0，`LICENSE` |
| Twilio Paste | `paste` | `2020.05.19`；`080ab85` | MIT，`LICENSE` |
| HPE Grommet | `grommet` | 2.58.0；`ec6cbf0` | Apache-2.0，`LICENSE` |

补充资料：

| 来源 | 本地路径 | 版本/规模线索 | 使用边界 |
| --- | --- | --- | --- |
| Apple Human Interface Guidelines | `<local-design-library>\design-corpus\apple\hig` | 175 个文件、约 2.2 MB | 官方站点条款，只复用原则，不复制品牌资产 |
| Atlassian Design System | `<local-design-library>\design-corpus\atlassian` | 480 个文件、约 72.5 MB | 官方站点条款，适合查 token、焦点、浮层和组件规则 |
| 本地 UI SQLite 索引 | `<local-design-library>\ui-database\ui-design.db` | 约 127 MB | 只读查询；源证据仍在 `design-corpus` |

### 3.3 `node_modules` 直接证据

| 依赖 | 路径 | 版本 | 许可证 | 可复用范围 |
| --- | --- | --- | --- | --- |
| Radix Popover | `D:\tong\frontend\node_modules\@radix-ui\react-popover` | 1.1.6 | MIT | 参考焦点、浮层和键盘行为，不直接套到 WinForms |
| Radix Popper | `D:\tong\frontend\node_modules\@radix-ui\react-popper` | 1.2.2 | MIT | 参考锚点定位与碰撞处理 |
| Radix Focus Scope | `D:\tong\frontend\node_modules\@radix-ui\react-focus-scope` | 1.1.2 | MIT | 参考模态焦点边界 |
| Floating UI DOM | `D:\tong\frontend\node_modules\@floating-ui\dom` | 1.8.0 | MIT | 参考浮层翻转、边界和最大高度 |
| Floating UI React DOM | `D:\tong\frontend\node_modules\@floating-ui\react-dom` | 2.1.9 | MIT | 参考共享定位基础设施 |

### 3.4 项目内查询方式

全局资料库只用于只读取证，不把 AMD Mobile Power 的项目结论写回全局数据库：

```powershell
cd <local-design-library>\ui-database
python .\scripts\query.py stats
python .\scripts\query.py search "focus ring"
python .\scripts\query.py component data-table
python .\scripts\query.py principle "tonal surface"
python .\scripts\query.py token radius
```

本项目按以下分工使用资料：

| 设计问题 | 优先查询 |
| --- | --- |
| 数字、表格、遥测密度 | Ant Design、Primer、PatternFly |
| 桌面焦点、键盘、禁用态 | Fluent UI、Apple HIG、Atlassian |
| 表面层级、边框、圆角 | Carbon、Spectrum、Paste |
| 状态、错误和下一步动作 | Atlassian、Polaris |
| 浮层碰撞、翻转和最大高度 | Floating UI、Radix、React Aria |

查询结果只能作为证据。最终规则必须结合 WinForms 能力、`560x400` 尺寸预算、
现有源码和真实窗口截图，记录在本文组件契约中。

## 4. 本地来源到本项目规则

下表区分“资料来源事实”与“本项目建议”。第三方数值是基准证据，不是必须照抄的品牌皮肤。

| 本地来源 | 可复用规则 | 本项目建议 |
| --- | --- | --- |
| Ant Design：`repos\ant-design\docs\spec\font.en-US.md:31` | 需要纵向比较的数字使用 tabular figures | 功耗、温度、上限和时间使用稳定数字宽度；值右对齐 |
| Primer：`repos\primer-design\content\components\data-table.mdx:113` | 数值右对齐，优先使用等宽数字 | 四个遥测值采用固定列宽和统一小数位 |
| Atlassian：`atlassian\pages\components__tokens__all-tokens.md:3248-3282` | 圆角按 badge、control、container、overlay 和 full 分级 | WinForms 普通控件维持轻量矩形；若自绘，控制 4px、容器 8px，不使用胶囊堆叠 |
| Apple HIG：`apple\hig\design\Human-Interface-Guidelines\boxes.md:26` | 优先用间距和对齐表达分组，避免嵌套盒子 | 简单模式只保留一个遥测表面，不再给每个指标套卡片 |
| Apple HIG：`apple\hig\design\Human-Interface-Guidelines\buttons.md:32` | 按钮需要足够命中区和周围空间 | 桌面主按钮高度至少 36-40px；预设按钮至少 36px；不要缩小可点击区 |
| Paste：`repos\paste\packages\paste-website\src\pages\foundations\elevation\index.mdx:143` | 亮色主题的抬升表面可略深，暗色主题可略亮 | 继续使用 canvas/surface/muted 的表面层级，不靠阴影制造层级 |
| Fluent：`repos\fluentui\apps\public-docsite-v9-headless\src\Accessibility\Overlays.mdx:100` | 强制颜色模式会移除阴影，仍需可见边界 | 焦点、输入边界和禁用原因不能只依赖颜色或阴影 |
| Atlassian：`atlassian\pages\components__button__usage.md:201` | 禁用按钮本身不能解释为什么不可用 | 简单模式持续显示“只读 / 写入已锁定 / 平台不支持”及下一步 |
| `ui-database` principle `focus-is-a-contract` | 键盘焦点必须清晰可见 | 所有按钮、数字输入、预设和模式切换提供 2px 焦点环与可见间隔 |
| `ui-database` principle `tonal-surface-hierarchy` | 层级先靠语义表面，再用阴影 | 简单模式使用单一背景和一块遥测表面；状态用语义底色 |
| `ui-database` component `data-table` | 数据需要边界、对齐、溢出和空态契约 | 遥测区定义为固定四列指标组件，不把 `a / b` 塞进窄标签 |

## 5. 当前简单模式源码事实

### 5.1 入口与文件

| 文件 | 当前职责 | 维护注意 |
| --- | --- | --- |
| `src\AmdMobilePower.Gui\MainForm.cs:181-248` | 建窗、固定简单模式尺寸、装配简单/高级页面 | 简单模式初始 `ClientSize=560x400` |
| `src\AmdMobilePower.Gui\MainForm.cs:375-384` | 简单模式外层 Panel | 实际调用 `BuildMiniSimpleContent()` |
| `src\AmdMobilePower.Gui\MainForm.cs:716-1058` | 当前实际简单模式内容 | 本文所有布局结论以此为准 |
| `src\AmdMobilePower.Gui\MainForm.cs:387-714` | 旧 `BuildSimpleContent()` | 当前无调用；仍有字段初始化代码，易让维护者误改 |
| `src\AmdMobilePower.Gui\Ui\AppTheme.cs:5-31` | 颜色和字体 token | 当前颜色仍以静态字段为主，缺少完整语义状态层 |
| `src\AmdMobilePower.Gui\Ui\AppTheme.cs:33-95` | Label、Button、NumberInput 工厂 | 默认 Label 开自动省略，具体页面再逐项覆盖 |
| `src\AmdMobilePower.Gui\Ui\FlatTextButton.cs:43-55` | 自绘焦点矩形 | 有焦点线索，但仅 3px 内缩的默认虚线，强调不足 |
| `src\AmdMobilePower.Gui\Ui\SpinlessNumericUpDown.cs:12-23` | 隐藏原生数字按钮 | 依赖 NumericUpDown 内部子控件顺序，升级或视觉状态时较脆弱 |

### 5.2 实际尺寸计算

以下为 `96 DPI` 的逻辑像素事实：

| 区域 | 计算 | 结果 |
| --- | --- | --- |
| 窗口客户区 | 源码固定值 | `560 x 400` |
| Header | 简单模式固定行高 | `64` |
| 页脚 | 简单模式固定行高 | `0` |
| Body | `400 - 64` | `336` |
| Body 内宽 | `560 - 12 - 12` | `536` |
| Body 内高 | `336 - 10 - 10` | `316` |
| 底部状态 | 固定行高 | `32` |
| 主 shell 高度 | `316 - 32` | `284` |
| 左轨 | 固定列宽 | `132` |
| 左右间隔 | 固定列宽 | `14` |
| 主列宽度 | `536 - 132 - 14` | `390` |
| 主列实时块 | 固定列宽 | `178` |
| 实时/指标间隔 | 固定列宽 | `14` |
| 指标块宽度 | `390 - 178 - 14` | `198` |
| 指标内容宽 | `198 - 10 - 10` | `178` |
| 指标标签列 | 固定列宽 | `86` |
| 指标值列 | `178 - 86` | `92` |

### 5.3 具体问题

| 问题 | 源码证据 | 用户可见影响 | 结论等级 |
| --- | --- | --- | --- |
| 左轨压缩主信息区 | `MainForm.cs:739-795` | 主列只剩约 `390px`，目标和遥测空间被迫变窄 | 源码事实 |
| 预设纵向堆叠 | `MainForm.cs:753-795` 使用 3 个 `48px` 按钮和独立“编辑预设” | 左轨像导航列表，和主操作竞争；扫描路径先左后右，不符合“目标 -> 应用”的主要任务 | 源码事实与设计判断 |
| 两个实心强调操作 | 预设选中使用 `Accent`，见 `MainForm.cs:2132-2147`；应用按钮也用 `Accent`，见 `MainForm.cs:947-960` | “当前预设”和“应用”看起来同为最高优先级 | 源码事实与设计判断 |
| 指标值可能裁切 | 指标值列 `92px`，`AutoEllipsis=false`，见 `MainForm.cs:1025-1032` | 实测 `105.0 / 105.0 °C` 约 `93px`，三字温度或本地化后更容易贴边/裁字 | 源码事实 + 本机文本测量 |
| 状态正文可能裁切 | 状态高 `32px`、`AutoEllipsis=false`，见 `MainForm.cs:1043-1055` | 文本长度只按字符数判断，未按可用宽度测量；长中文或高 DPI 下会裁切 | 源码事实 |
| 错误详情被过度压缩 | `MainForm.cs:2540-2563` 对超过 40 字符的通用错误只显示“打开高级模式” | 用户知道失败，却不知道首要修复动作；安全相关应用尤其不应只给模糊提示 | 源码事实与设计判断 |
| 只读状态没有实际入口 | `MainForm.cs:877-881` 创建新 `_simpleWriteStateLabel` 并设为不可见，`MainForm.cs:1695-1696` 只更新文字，未把它加入当前页面控件树 | 简单模式无法持续解释为什么“应用”不可用 | 源码事实 |
| 禁用态依赖按钮 | `MainForm.cs:2495-2510` 主要改颜色和 `Enabled` | 用户无法从按钮本身得知是只读、平台不支持还是异步处理中 | 源码事实 |
| 状态条沿用左轨缩进 | `MainForm.cs:1050` 设置 `Padding.Left=146` | 一旦删除左轨，状态文本仍会人为缩进，浪费宽度 | 源码事实 |
| DPI 风险 | `MainForm.cs:201` 为 `AutoScaleMode.None`；`MainForm.cs:2449-2477` 只缩放窗口外框尺寸 | 固定行高、列宽和字体在 125%/150% 下可能不同步，需运行时复验 | 需运行时验证 |
| 焦点顺序不显式 | 简单模式控件普遍未设 `TabIndex`；仅有少量 `TabStop=true` | Tab 顺序依赖控件创建和 z-order，重构后容易漂移 | 源码事实 |
| 重复简单模式实现 | `BuildSimpleContent()` 当前无调用，实际入口是 `BuildMiniSimpleContent()` | 后续维护者可能修改错误方法，造成“代码改了 UI 没变” | 源码事实 |

本机文本测量补充：

| 文本 | 字体 | 测量宽度 |
| --- | --- | ---: |
| `25.0 / 40.0 W` | Microsoft YaHei UI 9pt Bold | `79px` |
| `105.0 / 105.0 °C` | Microsoft YaHei UI 9pt Bold | `93px` |
| `旧版 RyzenAdj 正在占用，退出后再试` | Microsoft YaHei UI 9pt | `205px` |
| `硬件读取超时，请重启 Windows 后再试` | Microsoft YaHei UI 9pt | `217px` |

测量只证明文本本身所需宽度，不代表已完成窗口运行截图验证。

## 6. 设计 token 建议

### 6.1 颜色

现有颜色来自 `AppTheme.cs`，建议保留整体青绿 + 深灰绿色调，补齐语义边界和焦点角色。

| Token | 建议值 | 来源 | 用途 |
| --- | --- | --- | --- |
| `color.canvas` | `#F2F5F2` | 源码现有 `Background` | 页面底色 |
| `color.header` | `#162221` | 源码现有 `Header` | 顶栏 |
| `color.surface` | `#FFFFFF` | 源码现有 `Surface` | 输入和主要表面 |
| `color.surface-muted` | `#F7F9F7` | 源码现有 `SurfaceMuted` | 预设条、遥测区、状态条 |
| `color.border-subtle` | `#D8E0DB` | 源码现有 `Border` | 非关键分隔 |
| `color.border-strong` | `#87958F` | 建议新增 | 输入边界；对白色约 `3.12:1` |
| `color.text` | `#1B2625` | 源码现有 `Text` | 主文字 |
| `color.text-muted` | `#606E6B` | 源码现有 `TextMuted` | 标签、单位；对白色约 `5.33:1` |
| `color.accent` | `#0C8477` | 源码现有 `Accent` | 主操作、实时值 |
| `color.accent-hover` | `#096E63` | 源码现有 `AccentHover` | Hover/按下、选中预设文字 |
| `color.accent-soft` | `#E2F5F1` | 源码现有 `AccentSoft` | 选中预设背景 |
| `color.battery` | `#C3701C` | 源码现有 `Battery` | 电池数值和徽标 |
| `color.battery-soft` | `#FFF6E8` | 源码现有 `BatterySoft` | 电池徽标背景 |
| `color.warning` | `#B45309` | 源码现有 `Warning` | 固件限制、恢复提示 |
| `color.warning-soft` | `#FFF7ED` | 源码现有 `WarningSoft` | 警告条背景 |
| `color.error` | `#B91C1C` | 源码现有 `Error` | 失败状态 |
| `color.error-soft` | `#FEF2F2` | 源码现有 `ErrorSoft` | 错误条背景 |
| `color.disabled-bg` | `#CDD5D1` | 源码现有禁用值 | 禁用按钮 |
| `color.disabled-text` | `#36433F` | 源码现有禁用值 | 禁用按钮文字 |
| `color.focus-light` | `#096E63` | 建议新增语义别名 | 浅色表面焦点环 |
| `color.focus-dark` | `#FFFFFF` | 建议新增语义别名 | 深色顶栏焦点环 |

提示：`color.border-subtle` 对白色只有约 `1.35:1`，适合分隔线，不足以作为输入控件边界；
输入边缘应使用 `color.border-strong`。

### 6.2 字体

| Token | 建议值 | 用途 |
| --- | --- | --- |
| `font.title` | Segoe UI Variable Display 14pt Bold | 简单模式品牌标题 |
| `font.display` | Segoe UI Variable Display 28pt Bold | 实时 STAPM 大数字 |
| `font.metric` | Microsoft YaHei UI 12-13pt Bold | 四个遥测实际值 |
| `font.body` | Microsoft YaHei UI 9pt | 正文、按钮、状态 |
| `font.body-bold` | Microsoft YaHei UI 9pt Bold | 目标标签、主按钮 |
| `font.caption` | Microsoft YaHei UI 8.25pt | 范围、单位、上限、平台 |
| `font.caption-bold` | Microsoft YaHei UI 8.25pt Bold | 电源徽标、状态标签 |

约束：

- 不按窗口宽度缩放字体。
- 所有功耗、温度和上限使用固定小数位与稳定数字宽度。
- 一个区域只允许一个 Display 级数字；简单模式中只有实时 STAPM 使用 28pt。

### 6.3 间距与尺寸

| Token | 建议值 | 用途 |
| --- | --- | --- |
| `space-1` | `4px` | 图标与文字、单位与数值 |
| `space-2` | `8px` | 同组控件间隔 |
| `space-3` | `12px` | 页面内边距、组间距 |
| `space-4` | `16px` | 主分区间距 |
| `space-5` | `24px` | 高级模式页面边距 |
| `window.simple` | `560 x 400` 逻辑像素 | 固定简单模式 |
| `header.simple` | `52px` | 简单模式顶栏 |
| `control.compact` | `28px` | 模式切换、置顶 |
| `control.secondary` | `36px` | 预设、编辑 |
| `control.primary` | `40px` | 目标输入、应用 |
| `radius.control` | `4px`，自绘时 | 输入和按钮 |
| `radius.container` | `8px`，自绘时 | 真正的独立容器 |
| `focus.ring` | `2px` + `1px` 间隔 | 所有键盘焦点 |

### 6.4 状态

| 状态 | 视觉规则 | 辅助线索 |
| --- | --- | --- |
| 默认 | 白底、深色文字、强边框 | 文字标签完整 |
| Hover | 浅灰绿底或加深主色 | 鼠标指针，不改变控件尺寸 |
| Pressed | 比 Hover 再深一档 | 保留文字对比度 |
| Focus | 2px 高对比外环 + 1px 间隔 | 不裁剪，不依赖颜色唯一表达 |
| Selected preset | `accent-soft` 背景、`accent-hover` 文字、1px accent 边框 | 前缀/勾选或 `aria` 等价状态 |
| Disabled | `disabled-bg` + `disabled-text` | 邻近持续说明原因 |
| Read-only | 状态标签“只读模式” | 禁用应用按钮，但解释不丢失 |
| Unsupported | 错误语义标签“平台不支持” | 同时说明查看高级诊断 |
| Applying | 主按钮文字改为“正在应用…”，保持宽度 | 输入暂时不可编辑，状态条说明 |
| Success | 正常状态条，短暂提示后保留可追溯结果 | 不只靠绿色 |
| Warning/clamp | 警告条显示实际生效值 | 同时说明 Fast/Slow 与 STAPM 的区别 |
| Error | 错误条显示“问题 + 下一步动作” | 详情可进入高级模式，但首行动作必须保留 |

## 7. 组件模式

### 7.1 `CompactHeader`

组成：

- 左侧：`AMD Power` + 一行 `CPU · SMU`。
- 中部：`简洁 | 高级` 分段模式。
- 右侧：置顶图标/文字切换。

契约：

- 固定高度 `52px`。
- 模式切换整体宽 `116px`，每项最小 `28px` 高。
- 置顶按钮不改变顶栏宽度。
- 焦点环使用深色背景上的白色 2px 环。
- 模式切换要有 `AccessibleName` 和选中状态；不能只靠底色。

### 7.2 `LivePowerHero`

组成：

- `STAPM 实时` 小标题。
- 28pt 大数字 + 小号 `W`。
- 电源类型徽标：`AC` / `电池` / `未知`。
- 第二行：`上限 40.0 W`。

约束：

- 大数字宽度预留至少 `130px`。
- 数值没有更新时显示 `--`，不显示 `NaN` 或空字符串。
- 电池状态改变颜色时同步改变徽标文字，不只用橙色。

### 7.3 `PowerTargetRow`

组成：

- `目标功耗` 标签。
- 范围提示，例如 `5-60 W`。
- 数值输入 `96-112px`。
- `W` 单位。
- 主操作按钮：`应用 25 W`。

建议采用显式 Stepper：

```text
目标功耗  5-60 W
[-] [ 25 ] W   [ 应用 25 W ]
```

契约：

- 输入高度 `40px`，主按钮高度 `40px`。
- 数字输入不依赖隐藏原生 spinner；若保留 `SpinlessNumericUpDown`，必须补测试防止内部实现变化。
- 主按钮宽度至少 `128px`，文字长度变化时不改变布局。
- 禁用时保持按钮宽度，并由状态条解释原因。
- 键盘顺序：数字输入 -> 应用 -> 预设 1/2/3 -> 编辑预设。

### 7.4 `PresetStrip`

组成：

- `快捷功耗` 标签。
- 三个横向互斥预设。
- 右侧“编辑预设”次要操作。

契约：

- 预设按钮高 `36px`，可点击区域不因文字变短而缩小。
- 选中态使用软底色，不和应用主按钮一样使用实心 accent。
- 预设值超过平台上限时禁用，并显示可用范围或 tooltip。
- 三个按钮宽度可等分，长预设值不得挤压“编辑预设”。

### 7.5 `TelemetryMatrix`

单一表面内的四列指标：

| 列 | 主值 | 次值 |
| --- | --- | --- |
| STAPM | 实际 W | 动态上限 W |
| PPT Fast | 实际 W | 有效上限 W |
| PPT Slow | 实际 W | 有效上限 W |
| CPU 温度 | 实际 °C | 上限 °C |

契约：

- 四列等宽，默认每列约 `128px`。
- 标签、实际值、上限分三行；不再使用 `实际 / 上限` 塞入单个窄 Label。
- 实际值 12-13pt 粗体，上限 8.25pt 弱文本。
- 所有指标右对齐或统一起始线；不得一列左对齐、另一列右对齐。
- 缺失值显示 `--`，并保留单位位置。
- 只使用一个 `surface-muted` 背景，不给每个指标加独立卡片。

### 7.6 `StatusBanner`

组成：

- 左侧固定状态标签：`只读` / `已解锁` / `警告` / `失败`。
- 中间首行消息。
- 可选右侧“查看详情”入口。

建议消息模型：

```text
severity: normal | warning | error
shortText: 用户首要理解的问题
nextAction: 可执行下一步
detail: 高级模式中的完整诊断
updatedAt: 可选时间
```

不要在 UI 层用 `Contains()` 猜测错误含义。当前 `CompactSimpleStatus()` 的字符串匹配应改为结构化状态，
至少区分：只读、平台不支持、worker 离线、旧版占用、硬件超时、固件 clamp、传输失败。

## 8. `560x400` 布局重排方案

### 8.1 目标线框

```text
┌────────────────────────────────────────────────────────┐
│ AMD Power                         [简洁|高级] [置顶]   │ 52
│ Ryzen 7 8845HS · SMU 15                               │
├────────────────────────────────────────────────────────┤
│ STAPM 实时            目标功耗  5-60 W                 │ 84
│ 25.0 W  [AC]          [-] [25] W [应用 25 W]           │
│ 上限 40.0 W                                            │
│                                                        │ 10
│ 快捷功耗   [12 W] [25 W] [45 W]              [编辑]   │ 40
│                                                        │ 10
│ STAPM       PPT Fast     PPT Slow        CPU 温度      │ 134
│ 25.0 W      25.0 W       25.0 W          68.0 °C        │
│ 上限 40.0W  上限 25.0W   上限 25.0W      上限 105.0°C   │
│                                                        │
│ [只读]  工具处于只读模式，写入未解锁          [详情]   │ 36
└────────────────────────────────────────────────────────┘
```

尺寸为 `96 DPI` 逻辑像素；在更高 DPI 下应对所有行高、列宽、字体和间距统一缩放，
不能只放大窗口外框。

### 8.2 可执行行规格

| 行 | 高度 | 说明 |
| --- | ---: | --- |
| Header | `52` | 品牌、平台、模式、置顶 |
| Body padding | 上/下 `12` | 左右统一 `12` |
| Hero | `84` | 左实时、右目标 |
| Gap | `10` | 主信息到预设 |
| Preset strip | `40` | 横向三预设 + 编辑 |
| Gap | `10` | 预设到遥测 |
| Telemetry | `134` | 四列单表面 |
| Gap | `10` | 遥测到状态 |
| Status | `36` | 状态标签 + 消息 + 详情 |

计算：

```text
400 - 52 header = 348 body
348 - 12 - 12 padding = 324 content height
84 + 10 + 40 + 10 + 134 + 10 + 36 = 324
```

### 8.3 Hero 内部尺寸

| 区域 | 宽度 | 说明 |
| --- | ---: | --- |
| Body 内容宽 | `536` | `560 - 12 - 12` |
| Live | `184` | 标题、大数字、上限 |
| Gap | `16` | 视觉分离 |
| Target | `336` | 标签、输入、单位、主按钮 |

Hero 右侧建议列宽：

```text
标签 64 + 间隔 8 + 输入 104 + 单位 20 + 间隔 8 + 应用 132 = 336
```

### 8.4 预设条内部尺寸

| 区域 | 建议尺寸 |
| --- | ---: |
| 标签 | `52` |
| 标签后间隔 | `8` |
| 三个预设 | 等分剩余宽，最小 `120` |
| 预设间隔 | `8` |
| 编辑按钮 | `40 x 36` 图标按钮或 `88 x 36` 文字按钮 |

在 `536px` 内容宽下，即使使用 `88px` 文字“编辑预设”，三个预设仍有足够空间。

### 8.5 状态条内部尺寸

| 区域 | 建议尺寸 |
| --- | ---: |
| 状态标签 | `64 x 24` |
| 左内边距 | `6` |
| 标签后间隔 | `8` |
| 中间消息 | 百分比填满 |
| 右侧详情入口 | `52 x 28`，仅需时显示 |

状态消息超过可用宽度时使用单行省略并提供完整 tooltip；错误首行必须写明问题和下一步，
不能直接降级为“打开高级模式查看详情”。

## 9. 关键改造顺序

1. 先删除简单模式左轨，把三个预设改为横向可选条。
2. 把遥测从 `178 + 14 + 198` 的两列组合改为四列等宽矩阵，消除 `92px` 窄值列。
3. 把 `_simpleWriteStateLabel` 纳入状态条，并建立“只读/锁定/不支持/处理中”原因模型。
4. 将选中预设从实心 accent 改为软底 + 强调文字，只保留“应用”为实心主操作。
5. 用逻辑像素缩放替换仅缩放窗口外框的 DPI 处理，并补 100%/125%/150% 截图验证。
6. 移除或明确隔离未使用的 `BuildSimpleContent()`，避免双重维护。
7. 显式设置 Tab 顺序和焦点环，补键盘、长文本、错误、只读和缺失值状态测试。

## 10. 验证清单

后续实现简单模式时，至少验证：

- `560x400` 在 100%、125%、150% 缩放下所有文字不裁切、不重叠。
- 目标值 `5`、`60`、三位数温度上限和所有缺失值均可见。
- 长 CPU 名、长 SMU、`旧版 RyzenAdj 正在占用`、硬件超时、BIOS/EC clamp 和通用异常均能显示首行动作。
- 只读模式、写入解锁、平台不支持、worker 离线、applying、成功、警告和错误状态。
- Tab/Shift+Tab 顺序与视觉阅读顺序一致；焦点环在深色顶栏、白底、软底和禁用旁均可见。
- 三个预设、编辑、目标输入和应用按钮的命中区不因状态改变而改变。
- 鼠标 hover/pressed、键盘操作、高对比模式和系统字体变化。
- 简单模式与高级模式切换后，目标值、预设和只读状态保持一致。

## 11. 维护规则

- 新设计规则先判断属于“本机资料事实、源码事实、设计建议”中的哪一类。
- 组件颜色、字号、行高、列宽和状态必须引用 token 或本文明确的结构规则，不新增无来源的魔法数字。
- 第三方代码复用前必须回到本机具体 `LICENSE` 文件核对；图标、字体和品牌资源可能另有条款。
- 若更改 `BuildMiniSimpleContent()`，同步更新本文第 5 节的入口、尺寸和问题表。
- 若后续补齐真实截图和运行时证据，应在本文追加“已验证状态”，不要把静态建议写成已验证事实。

## 12. 2026-11-10 实现记录

### 12.1 已落地布局

当前简洁模式由 `MainForm.BuildSimpleWorkspace()` 构建，窗口客户区仍为
`560x400` 逻辑像素，125% 缩放下实际客户区为 `700x500`。

| 区域 | 当前实现 |
| --- | --- |
| Header | `52px`：品牌、平台、简洁/高级切换、置顶 |
| Hero | `84px`：左侧实时 STAPM，右侧目标输入和应用 |
| Preset strip | `40px`：三个横向预设和编辑入口 |
| Telemetry | `134px`：STAPM、Fast、Slow、CPU 温度四列等宽矩阵 |
| Status | `36px`：写入状态徽标、当前消息和“详情”入口 |

关键实现：

- 删除简洁模式左侧 `132px` 预设轨，主内容恢复完整宽度。
- 预设选中状态改为浅强调底、强调边框和强调文字；“应用”保留唯一实心主操作。
- 实际值使用 `Consolas` 粗体稳定数字宽度，上限独立为弱文本行。
- `_simpleWriteStateLabel` 已加入状态条，持续显示只读、写入已解锁或平台不支持。
- 简洁模式启动目标来自第一个预设，当前默认 `12W`，不再被 profile 默认值覆盖为 `25W`。
- 读只模式和应用中的按钮禁用条件已修正为 `enabled && !_applying`。
- WinForms 自动 DPI 缩放完成后才设置补偿后的窗口客户区，避免右侧和底部裁切。
- 简洁和高级模式的电源栏都将系统报告的 AC 统一表述为“电源”，避免把
  USB-C 充电宝误显示为墙插交流电。
- 简洁模式不再在“目标功耗”左侧保留独立电源徽标；电源状态并入实时功耗下方
  的“动态上限 ... · 电源/电池”，避免未连接时出现 `--` 灰色占位残点。
- 实时功耗合并为单个 `12.0 W` 文本，不再保留会贴近目标区左缘的独立 `W` 小控件。
- 原生 `NumericUpDown` 已替换为纯数字文本输入，消除了隐藏 spinner 在 DPI 缩放下留下的灰色残点。

### 12.2 运行时验证证据

验证日期：2026-11-10；Windows 缩放：`125%`。

- 窗口截图：`docs/assets/gui-simple-12w-2026-11-10.png`。
- UI Automation 可读取完整的“写入已解锁”、三个 `12.0 W` 上限、
  `CPU 温度`、`上限 95.0 °C` 和状态消息。
- Windows OCR 可读取 `写入已解锁`、`12 W`、`上限 12 W`、`5-60W`、
  `PPT Fast`、`PPT Slow` 等关键文本。
- 像素检查确认目标输入左侧不再存在独立灰色 spinner 残点，且目标功耗左侧
  空白区无独立灰色状态点。
- 受控真实写入：
  - 目标 `10W`：STAPM/Fast/Slow 全部回读 `10.0W`。
  - 随后目标 `12W`：STAPM/Fast/Slow 全部回读 `12.0W`，实时 STAPM 约
    `11.7-12.0W`。
  - 测试电源为 USB-C 充电宝；系统仍将其报告为外接电源。
- `dotnet build AmdMobilePower.sln -c Release`：0 警告、0 错误。
- `dotnet test --solution AmdMobilePower.sln -c Release --no-build`：71/71 通过。

### 12.3 仍待验证

- 需要在 100% 和 150% 系统缩放下重复窗口截图；当前机器只完成了 125%。
- 需要键盘 Tab/Shift+Tab、焦点环、高对比模式和长错误文本截图。
- 需要第二台 AMD 笔记本验证 profile 差异和 DPI 行为。
- 真实写入证据仍需按 `HARDWARE_TEST_PROCEDURE.md` 完成独立 no-change
  baseline/restore 记录。
