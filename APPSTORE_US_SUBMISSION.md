# MacMediaTools — 美区 App Store 上架材料草稿

> 用途：直接复制到 App Store Connect（App Store 美国区）对应字段。
> 准备日期：2026-07-16
> 区域策略：首发仅选 **United States**（额外文书最少），上线稳定后再扩展到全部 175 个 storefront。

---

## 一、基础信息（App Store Connect 必填）

| 字段 | 内容 |
|------|------|
| 名称 (Name) | MacMediaTools |
| 副标题 (Subtitle) | 本地视频/音频/图片处理工具箱 |
| 类别 (Primary Category) | Utilities（工具） |
| 类别 (Secondary) | Photo & Video（照片与视频） |
| 内容版权 (Copyright) | `2026 RMTG5D` |
| 年龄评级 (Age Rating) | **4+**（无不良内容，纯本地工具） |
| 价格 | Free（建议免费首发，降低门槛） |

---

## 二、关键词 (Keywords)

```
视频处理, 批量截图, 重复照片, 重复视频, 格式修复, 音视频合并, 画幅拼接, 本地工具, 媒体整理, 视频剪辑
```

（逗号分隔，不带空格；避免重复名称里已有的词）

---

## 三、描述 (Description)

**中文（主语言 zh-Hans）**

MacMediaTools 是一个完全在本机运行的 macOS 多媒体工具箱，所有处理都在本地完成，不上传、不联网、不收集任何用户数据。

主要功能：
- **宽高调整**：图片/视频裁剪 + 尺寸调整两阶段（可跳过），可视化裁剪框与实时拉伸预览。
- **视频片段整合**：批量选择、拖拽排序，拼接为单一视频，自动适配不同分辨率。
- **音视频处理**：视频与音频轨道合并、时间偏移/速度调整、音视频分离。
- **批量截图**：按时间间隔截取视频帧，支持清晰度评分与替代帧搜索、内容去重，可导出 ZIP。
- **重复照片检测**：递归扫描，SHA256 内容哈希精确匹配。
- **重复视频检测**：快速模式（时长/大小/分辨率）+ dHash 精细模式聚类。
- **文件复制工具**：智能复制媒体文件，自动检测重复并重命名。
- **画幅拼接**：图片/视频/GIF 自由混拼，拖拽定位、8 锚点缩放、逐轨混音导出。
- **媒体修复**：检测并修复扩展名不符、视频不兼容 QuickTime 的问题（无损，修复前逐项人工确认）。

所有功能均无需联网，保护你的隐私。

**English (可选，扩展英语区时填)**

MacMediaTools is a fully local macOS media toolbox. All processing happens on your Mac — no uploads, no network, no data collection.

Features: video crop & resize, video concatenation, audio/video merging, batch screenshots with quality filtering and ZIP export, duplicate photo/video detection (SHA256 / dHash), smart file copy, free-form canvas composition, and lossless media repair.

---

## 四、截图清单（App Store Connect 需上传）

Mac App Store 截图要求：至少为 **1280×800** 或 **1440×900** 等 Mac 尺寸，建议准备 5–7 张：

1. 宽高调整界面（裁剪框 + 预览）
2. 视频片段整合（列表拖拽排序）
3. 批量截图（帧网格 + 质量筛选）
4. 重复视频检测（对比面板）
5. 画幅拼接（画布编辑）
6. 媒体修复（检测列表 + 确认）
7. 首页/侧边栏导航总览

> 截图须为真实运行界面，不可用示意图；每张需体现实际功能，避免"误导性脑补"。

---

## 五、隐私问卷（App Store Connect → App Privacy）

本 App **不收集任何数据**，填写如下：

- "Does your app collect any user data?" → **No**
- Privacy Manifest 已内置：`NSPrivacyTracking = false`，无 `NSPrivacyCollectedDataTypes` 实质收集项。
- 因纯本地、无加密传输、无第三方 SDK，无需隐私政策 URL（若 ASC 要求，可填项目仓库或留空说明）。

---

## 六、出口合规 (Export Compliance)

- 本 App 仅使用 Apple 系统框架（AVFoundation/AVKit/CryptoKit），**不含自有加密、不含 VPN、不含加密通信**。
- 在 App Store Connect 的出口合规问题中选：**"My app does not use encryption..."** 或走免审的 exempt 路径（使用仅 Apple 标准加密的 App 通常自动豁免）。
- 无需提交 ERN 或国防贸易管制文件。

---

## 七、提交流程（操作顺序）

1. Xcode → 选 MacMediaTools scheme → Product → Archive（须用 Xcode 26+，已满足）。
2. Organizer → Distribute App → App Store Connect → 上传构建。
3. App Store Connect → 填上述名称/描述/关键词/截图/年龄评级。
4. Pricing and Availability → 仅勾 **United States**（Specific Countries）。
5. 提交审核（Submit for Review）。
6. 审核周期通常 1–2 天；若被拒，按 Guideline 编号修改后重新提交。

---

## 八、已知审核风险（提前规避）

- **Guideline 4.2（Design – Minimum Functionality）**：工具类 App 易被认定"功能与系统自带重复"。应对：描述中强调"批量/无损/多格式/本地隐私"等差异化价值。
- **Guideline 2.1（App Completeness）**：所有功能窗口须能打开且不崩溃。提交前手动点开每个功能验证。
- **隐私清单缺失**：已修复，确保 Info.plist 含 Privacy Manifest。
- **沙盒**：已完成输出目录面板化 + security-scoped bookmark，避免运行时写盘失败。
