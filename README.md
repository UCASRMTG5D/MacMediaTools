# MacMediaTools

**纯本地 macOS SwiftUI 多媒体工具箱** —— 视频/音频/图片处理、重复媒体检测、文件整理与媒体修复，全部在本机完成，不联网、不上传。

> **这份 README 是项目的背景知识入口。**
> 修改代码前读这里即可掌握：功能全貌、代码地图、状态归属、UI/算法/文件 IO 约定、构建安装标准和历史踩坑，不必通读整个 App。
> **强制规则：任何改动完成后都必须同步更新本文件对应章节**（见文末「文档维护规则」）。

最后更新：2026-10-31

---

## 0. 项目事实卡片

| 项目 | 现状 |
|------|------|
| 平台 | macOS 13.0+；Apple Silicon 优先，Intel 也可编译 |
| 语言 / UI | Swift 5 语言模式 + SwiftUI（`NavigationSplitView` 单窗口 + 独立帮助窗口） |
| 工程 | `MacMediaTools.xcodeproj`，显式文件成员（新增 `.swift` 必须加入 target） |
| 沙盒 | 开启 App Sandbox；仅 `user-selected.read-write` + `downloads.read-write` |
| 外部依赖 | 无。使用系统框架：SwiftUI / AppKit / AVFoundation / AVKit / CryptoKit / Accelerate / ImageIO / Compression |
| 功能数量 | 11 个（以 `Models/ToolFeature.swift` 为准） |
| 安装位置 | **只允许** `/Applications/MacMediaTools.app`（普通用户权限安装，免密码） |
| 构建脚本 | `./build.sh`（Release / arm64 / 免密码安装 + 签名兜底 + LaunchServices 注册） |

---

## 1. 功能一览

左侧导航顺序与 `ToolFeature.allCases` 完全一致：

| # | 功能 | 说明 |
|---|------|------|
| 1 | **宽高调整** | 图片/视频/GIF 的裁剪 + 尺寸调整（两阶段可跳过），可视化裁剪框 + 实时拉伸预览 |
| 2 | **视频片段整合** | 批量选择、拖拽排序，拼接为单一 MP4，不同分辨率自动居中/裁剪 |
| 3 | **音视频处理** | 视频与音频轨道合并、0.5x–2.0x 变速、时间偏移、轨道对齐、音视频分离 |
| 4 | **批量截图** | 按时间间隔截取视频帧，Sobel 清晰度评分 + ±1s 替代帧搜索 + 内容去重 + 四种筛选结果 |
| 5 | **停顿去除** | 按音频音量检测停顿，删掉静音段（每段保留前 0.5 秒），导出紧凑版视频 |
| 6 | **画幅拼接** | 图片/视频/GIF 混排到画布，自由拖动、8 锚点缩放/单轴拉伸、裁切、逐轨音量、导出 MP4 |
| 7 | **重复照片检测** | 快速模式 SHA256 精确匹配；精细模式 dHash + pHash 相似聚类 |
| 8 | **重复视频检测** | 快速模式按时长/大小/分辨率分组；精细模式分段 dHash 指纹 + 连通分量聚类 |
| 9 | **文件复制工具** | 智能复制媒体文件，目标同名时按内容/属性判重，不同内容自动编号 |
| 10 | **文件搜索** | 按文件名关键词递归搜索图片/视频，分组缩略图网格展示 |
| 11 | **媒体修复** | 修复图片扩展名不符、视频不兼容 QuickTime（改扩展名 / 无损 remux，不转码） |

---

## 2. 编译 / 运行 / 安装

### 2.1 开发运行

```bash
xed .                 # 用 Xcode 打开工程
# 选择 MacMediaTools scheme → Run（⌘R）
```

### 2.2 命令行构建并安装（推荐）

```bash
./build.sh
```

`build.sh` 的行为（修改安装逻辑前必读）：

1. `xcodebuild -project MacMediaTools.xcodeproj -scheme MacMediaTools -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath ./build/DerivedData build`
2. 构建产物：`./build/DerivedData/Build/Products/Release/MacMediaTools.app`
3. 签名校验失败时，用 `codesign --force --sign - --entitlements MacMediaTools/MacMediaTools.entitlements --options runtime` 做 ad-hoc 重签（沙盒 entitlements 必须保留）
4. 已安装版本二进制哈希与构建产物一致 → 跳过安装
5. 否则 `rm -rf /Applications/MacMediaTools.app` + `cp -R`，**不弹密码、不用 sudo**（`/Applications` 对 admin 组可写）
6. 自动清理历史误装的 `/Applications/Applications/MacMediaTools.app` 嵌套副本
7. 用 `lsregister -f` 刷新 LaunchServices 注册，保证从「应用程序」启动的是标准路径
8. 校验安装后的 mtime ≥ 构建产物 mtime

### 2.3 安装硬性标准

- **路径唯一**：只允许 `/Applications/MacMediaTools.app`。
- **禁止**安装到 `~/Applications/` 或任何其他目录。
- **禁止**出现 `/Applications/Applications/MacMediaTools.app` 这类嵌套目录。
- 当前用户拥有旧版本时，安装必须**免密码**完成；仅历史 root 属主版本需要一次性 `sudo rm -rf` 转换。
- 如果 `xcodebuild` 报 “You have not agreed to the Xcode license agreements”，需先执行一次 `sudo xcodebuild -license accept`（这是系统工具许可，不是 App 安装密码）。

### 2.4 发布

- GitHub Releases 提供 `.dmg`，拖入「应用程序」即可。
- 应用未做 Apple 公证，首次打开会被 Gatekeeper 拦截，属正常现象。放行方式：
  - 系统设置 → 隐私与安全性 → 「仍要打开」；
  - 或右键 App → 打开；
  - 或 `sudo xattr -rd com.apple.quarantine /Applications/MacMediaTools.app`。

---

## 3. 详细说明

### 1) 宽高调整

图片 / 视频 / GIF 通用：可选裁剪 → 可选尺寸调整 → 导出。

- **两阶段可跳过**：可只裁剪、只调整尺寸、或二者都做。
- **裁剪**：拖拽裁剪框移动/改大小，支持 1:1 / 4:3 / 3:2 / 16:9 / 3:4 / 2:3 / 9:16 预设；数字输入与裁剪框双向同步；内部使用归一化坐标并处理旋转元数据。
- **尺寸调整**：目标宽高输入、宽高比预设、恢复原始尺寸；缩放模式为拉伸（stretch）或 Aspect Fit（保持比例加黑边）。
- **实时拉伸预览**：开启尺寸调整后可预览效果并对比新旧分辨率。
- **输出**：可选择输出目录与文件名（目录安全书签持久化）；支持删除源文件（二次确认）。
- **实现**：`VideoToolkit`（视频/GIF 走 AVFoundation，图片走 ImageIO/CoreGraphics）。

### 2) 视频片段整合

多选视频 → 列表拖拽排序 → 指定输出宽高/文件名 → 拼接。

- 列表展示文件名与分辨率；默认输出分辨率取所有视频宽高的最大值。
- 分辨率不一致时：小于输出尺寸的居中加黑边，大于的裁掉边缘、保留中心。
- 支持手动指定输出宽高；导出 MP4。
- 实现：`VideoToolkit.exportConcatenated` + `AVMutableComposition`。

### 3) 音视频处理

视频轨道 + 音频轨道 → 变速/偏移/对齐 → 合并或分离。

- 视频、音频各自支持 **0.5x–2.0x**（步长 0.1）变速。
- 支持自由时间偏移；对齐方式：起始对齐 / 结束对齐 / 同步对齐。
- 撤销 / 重做最多 10 步。
- 合并输出 `.mov`；可从视频分离音频（`.m4a`）或分离视频（`.mov`）。
- 实现：`AudioVideoToolkit`（`AVMutableComposition` + `AVAssetExportSession`）。

### 4) 批量截图

选择视频 → 设时间范围/间隔 → 提取到内存 → 选择筛选结果 → 保存。

- **时间范围**：进度条拖拽选择 + 开始/结束时间输入 + 前 10 秒 / 前 30 秒 / 前 1 分钟 / 全视频快捷按钮。
- **间隔**：0.001–60 秒，滑块与数字输入双向同步。
- **输出格式**：PNG / JPEG（JPEG 质量 0.9）。
- **质量检查**：对每帧计算清晰度分数（BT.601 Y 通道 + Sobel 3×3 梯度均值）；无论阈值如何，都会在目标时间 ±1 秒内按 0.1 秒步长搜索更清晰帧并替换。
- **质量筛选**：按分数**百分位**保留前 N%（不是绝对阈值）。界面上的「质量阈值 85%」表示保留质量最高的 85% 帧。
- **内容去重**：16×16 灰度指纹逐像素差；采用**时序滑动窗口**，每帧只与“上一个保留帧”比较；相似时若新帧质量更高则替换保留帧。阈值越低越严格。
- **四种结果**：全部 / 质量筛选 / 去重 / 筛选+去重；保存时只保存当前选中模式的帧。
- **保护**：预计帧数 > 500 时先弹窗确认；支持暂停 / 继续 / 取消；实时进度与预计剩余时间。
- **快捷键**：空格播放/暂停，← / → 前后 1 秒。
- **文件名**：`screenshots_时-分-秒-毫秒.png`（来自帧时间戳，单批次内唯一）。
- **实现**：`VideoScreenshotExtractor`（actor，分块 + TaskGroup 并行提取）；服务层另有纯 Swift ZIP 打包 API `exportAsZip`，**当前界面未接入**。
- **布局注意**：本页曾因在 `NavigationSplitView` 详情区嵌套 `HSplitView` 导致侧边栏被挤成窄条，现已改为「单个 ScrollView + HStack 双栏」；不要再改回嵌套分栏（详见 BUG_KNOWLEDGE）。

### 5) 停顿去除

基于音频音量删除停顿，输出紧凑版视频。

- **判定参数**：音量阈值 -55…-25 dBFS（步长 1）；音频低于阈值且持续 ≥ 0.5 秒即判定为停顿。
- **保留策略**：每个停顿段只保留前 0.5 秒，其余删除。
- **分析结果**：原始时长、预计新时长、可节省时长/比例、停顿段数量。
- **导出**：默认文件名 `<原名>_去停顿.mp4`，输出目录可选；同名时自动追加 `_1`、`_2`…
- **实现**：`PauseRemover`（AVAssetReader 读取 32-bit float PCM，20ms 窗口 RMS → dB；导出用 `AVMutableComposition` 重组保留片段，H.264 重新编码）。
- 无音频轨道的视频会提示无法检测。

### 6) 画幅拼接

把多个图片 / 视频 / GIF 放到同一画布上做空间合成。

- **素材导入**：文件选择器一次可多选（图片 / 视频 / GIF），导入后在画布中自由拖动定位。
- **编辑模式**：移动 / 缩放 / 裁切三选一；编辑模式下画布不套 ScrollView，避免 DragGesture 被滚动拦截。
- **8 锚点手柄**：四角等比缩放，四边单轴拉伸。
- **裁切**：每个元素可独立裁切显示区域。
- **音量**：视频/GIF 元素可单独调 0–100% 音量，导出时混音。
- **画布与导出**：尺寸预设 1920×1080 / 1280×720 等 + 自定义；输出目录安全书签；文件名可改；导出 MP4（H.264 + AAC，30fps），时长取所有元素最大时长 + 1 秒（最少 2 秒）。
- **实现**：`SpatialCanvasView` + `CanvasElement` + `SpatialCanvasToolkit`（逐帧渲染到 CVPixelBuffer，再合并音频）。

### 7) 重复照片检测

递归扫描 → 两种模式。

**快速检测**
- 全文件 SHA256 精确匹配（分块读取，1MB/块）。
- 只报告内容完全一致的照片。

**精细检测**
- 每张照片计算 64 位 dHash + 64 位 pHash；先中心裁切 90% 以降低统一水印干扰。
- 两个哈希距离都 ≤ 各自阈值（AND）才建立相似边，再做连通分量聚类。
- 界面「相似度严格度 0–100%」映射为两套 Hamming 阈值：越严格阈值越小。
- 支持采样比例 10%–100%、自定义缓存目录；缓存默认写到 `<扫描目录>/hash_cache/picture`。
- 结果按簇展示，可并排对比、在 Finder 显示、移到废纸篓（二次确认）、本次忽略。

- 实现：`DuplicatePhotoScanModel` + `SimilarPhotoClusterer` + `MediaHashCache` + `FileHasher` + `FolderScanner`。

### 8) 重复视频检测

递归扫描 → 快速 / 精细两种模式；GIF 也会被扫描。

**快速检测**
- 分组键：时长（毫秒）+ 文件大小（字节）+ 分辨率。
- 三项完全一致才归为同一组。

**精细检测**
- 每部视频均匀抽取 10 个时间点，中心裁切 70% 后计算 64 位 dHash，组成 10 段指纹。
- 两视频逐段比较 Hamming 距离（≤ 10 视为该段匹配），匹配段比例 ≥ 50% 判定相似。
- 相似关系做连通分量聚类，按平均相似度排序。
- 支持采样比例 10%–100%、自定义缓存目录（默认 `<扫描目录>/hash_cache/video`）、调试模式。
- 提供并排对比面板：同步播放/进度、全局与单路音量调节。

- 实现：`DuplicateVideoScanModel` + `SimilarVideoClusterer` + `MediaHashCache`。

### 9) 文件复制工具

选择源媒体文件与目标文件夹 → 复制。

- 目标不存在同名文件：直接复制。
- 目标存在同名文件：
  - 图片：SHA256 相同 → 跳过并报告「内容完全相同」；不同 → 自动改名 `原名_1.ext`。
  - 视频：时长 + 分辨率都相同 → 跳过并报告；不同 → 自动改名。
- 界面显示选择列表、进度、当前文件、重复报告与日志。
- 实现：`FileCopyView` + `FileHasher` + AVFoundation。

### 10) 文件搜索

选择文件夹 + 输入关键词 → 递归搜索。

- 关键词匹配不区分大小写；关键词为空时列出全部媒体。
- 结果按「图片 / 视频」分组，组内按创建时间倒序。
- 缩略图网格显示，缩略图尺寸 60–200 可调。
- 点击缩略图用默认应用打开，支持在 Finder 中显示。
- 只读任务，不参与 `WorkManager` 排他调度，可与其他任务并行。
- 实现：`FileSearchView` → `FileSearchModel` → `FinderSearchService`。

### 11) 媒体修复

检测并修复媒体文件的格式/标签问题，检测阶段只读，修复前人工勾选确认。

- **图片扩展名不符**：用 ImageIO 读取真实 UTI，与扩展名不一致时改扩展名（零画质损失）。例如 WebP 内容命名为 `.jpg` 会导致 Preview 显示「已锁定」。
- **视频不兼容 QuickTime**：扩展名属于 avi / mkv / wmv / flv / webm / 3gp 等非常规容器时，无损 remux 到 `.mp4`（拷贝音视频流，不重新编码）。
- 检测范围：全部 / 仅图片 / 仅视频；支持选择文件，或递归扫描整个文件夹。
- 结果按图片/视频分组，逐项显示当前问题与建议动作；全选/取消后点「开始修复」才写盘。
- 实现：`MediaRepairView` → `MediaRepairModel` → `MediaRepair`（`MediaRepairService.swift`）。

---

## 4. 架构与数据流

### 4.1 分层

```
NavigationSplitView (RootView)
   │  selection: ToolFeature
   ▼
Feature View (SwiftUI, @State / @StateObject / @ObservedObject)
   │  用户操作
   ▼
Service 层（actor / static enum / Observable 模型）
   │
   ├─ AVFoundation / AVKit     视频、音频、帧提取、导出
   ├─ CryptoKit                SHA256
   ├─ ImageIO / CoreGraphics   图片读取、缩放、像素处理
   ├─ Accelerate               pHash/dHash（vDSP）
   ├─ Compression              ZIP deflate
   └─ FileManager              ｜扫描、复制、重命名、缓存
```

- Feature View 负责交互与展示；耗时逻辑放在 Service。
- Service 不依赖 SwiftUI 视图；允许使用 AppKit（如 `NSWorkspace`、`NSBitmapImageRep`）。
- 跨功能共享状态由 `RootView` 持有，保证切换功能时任务不中断。

### 4.2 状态归属（改状态前先看这里）

| 状态 | 持有者 | 说明 |
|------|--------|------|
| 当前功能选择 | `RootView.@State selection` | `ToolFeature?` |
| 重复照片扫描 | `RootView.@StateObject duplicatePhotoScan` | 切走再回来扫描继续 |
| 重复视频扫描 | `RootView.@StateObject duplicateVideoScan` | 同上 |
| 媒体修复检测/修复 | `RootView.@StateObject mediaRepair` | 同上 |
| 文件搜索 | `RootView.@StateObject fileSearch` | 只读任务，可并行 |
| 其余功能状态 | 各自 Feature View 内的 `@State` | 切走即销毁 |
| 画幅拼接状态 | `SpatialCanvasView` 内的 Canvas store | 随视图销毁 |

单例 / 共享服务：

- `WorkManager.shared`：任务排他/并行冲突仲裁。
- `OperationLogManager.shared`：操作日志（UserDefaults 持久化）。
- `SecurityBookmarkStore.shared`：沙盒安全书签（actor）。
- `VideoScreenshotExtractor.shared`、`PauseRemover.shared`、`SpatialCanvasToolkit.shared`：无状态 worker actor。

### 4.3 统一服务基类

`Services/Infrastructure/BaseObservableService.swift`

- 提供 `isWorking`、`progress`、`errorMessage`、`cancel()`、`clear()`。
- `runAsync` / `runSimple` 统一在后台执行任务并把进度回调切回 `MainActor`。
- 扫描类模型（`DuplicatePhotoScanModel`、`DuplicateVideoScanModel`、`MediaRepairModel`、`FileSearchModel`）都继承它。

### 4.4 任务冲突（WorkManager）

- 旧接口 `requestStart(feature)`：全应用串行；有其他任务时弹「打断 / 排队 / 取消」。
- 新接口 `requestStart(feature, writeDir:)`：按**写入目录**判断冲突。
  - 两个任务写同一目录或目录存在包含关系 → `.conflict`，禁止并行。
  - 无目录冲突但有任务在跑 → `.choice`，允许替换 / 排队 / 并行。
  - 只读任务（`writeDir == nil`，如文件搜索、快速哈希）不冲突。
- 所有任务结束必须 `defer { WorkManager.shared.finishWork(...) }`。
- 重复照片/视频使用 `WorkConflictDialog` 展示裁决结果。

### 4.5 数据、缓存与持久化

**沙盒**：`MacMediaTools.entitlements` 开启 App Sandbox，只有用户选择文件/目录和 Downloads 的读写权限。

**安全书签**（`SecurityBookmarkStore`，存 UserDefaults）：

| Key | 使用方 |
|-----|--------|
| `VideoCropResizeOutputFolder` | 宽高调整输出目录 |
| `VideoConcatOutputFolder` | 视频拼接输出目录 |
| `VideoScreenshotExtractorOutputDirectory` | 批量截图输出目录 |
| `SpatialCanvasOutputFolder` | 画幅拼接输出目录 |

**UserDefaults Keys**（`MediaToolsUtilities.swift`）：

- `VideoScreenshotExtractorLogs`：批量截图日志。
- `OperationLogs`：通用操作日志。
- `LastExtractionTask`：任务状态 JSON（保存/读取方法已存在，**恢复 UI 未接入**）。

**哈希缓存**（`MediaHashCache`）：

- 默认 `<扫描目录>/hash_cache/picture`、`<扫描目录>/hash_cache/video`，可自定义目录，可关闭子目录。
- 缓存条目包含文件大小、修改时间、时长、分辨率、码率、帧率、分段哈希等；用于加速重复检测。

### 4.6 线程与并发约定

- UI 更新一律回到 `MainActor`；`@MainActor` 标注模型/服务入口。
- 文件夹递归扫描、批量提取、哈希计算放后台：`Task.detached(priority: .userInitiated)` 或 `BaseObservableService.runAsync`。
- 批量帧提取使用 `withThrowingTaskGroup` 分块并行；进度通过回调汇总。
- 禁止空 `catch`；错误转成用户可读的中文提示。

---

## 5. 代码地图

```
MacMediaTools/
├── MacMediaToolsApp.swift              # @main、主窗口、帮助窗口、帮助菜单
├── RootView.swift                      # NavigationSplitView + 功能切换 + 共享扫描状态
├── WelcomeDefaultView.swift            # 未选择功能时的欢迎页（含编译时间）
├── MediaToolsUtilities.swift           # 扩展名集合、时间格式化/解析、预设、UserDefaults Keys、删除确认
├── Info.plist / MacMediaTools.entitlements
├── Models/
│   ├── ToolFeature.swift               # 11 个功能枚举（导航顺序）
│   └── CanvasElement.swift             # 画布元素、手柄位置、画布设置
├── Components/
│   ├── OpenPanelButton.swift           # 文件/文件夹选择按钮（NSOpenPanel）
│   ├── VideoProgressSlider.swift       # 视频范围/进度选择滑块
│   ├── VideoComparisonPanel.swift      # 多视频并排同步播放对比（含 GIF）
│   ├── PhotoComparisonPanel.swift      # 照片对比
│   ├── WorkConflictDialog.swift        # 任务冲突裁决弹窗
│   ├── CanvasElementView.swift         # 画布元素渲染
│   ├── CanvasResizeHandles.swift       # 8 锚点缩放手柄
│   ├── StandardViews.swift             # ⚠️ 备用统一布局模板，当前无功能页使用
│   └── CommonComponents.swift          # ⚠️ 备用通用组件，当前无功能页使用
├── Features/
│   ├── VideoCropResizeView.swift       # 宽高调整主视图
│   ├── CropOverlay.swift               # 可拖拽裁剪框
│   ├── CropSettingsView.swift          # 裁剪参数/预设
│   ├── ResizeSettingsView.swift        # 尺寸参数/预设/预览
│   ├── OutputSettingsView.swift        # 输出目录/文件名/删除源文件
│   ├── VideoConcatView.swift           # 视频拼接
│   ├── AudioVideoEditorView.swift      # 音视频编辑
│   ├── AudioTimelineView.swift         # 音频波形时间轴
│   ├── TimeRulerView.swift             # 时间刻度
│   ├── TrackBarView.swift              # 轨道条
│   ├── TrackRowView.swift              # 轨道行
│   ├── VideoScreenshotExtractorView.swift # 批量截图
│   ├── ThumbnailPreviewPanel.swift     # 截图缩略图网格 + 选中预览
│   ├── FrameThumbnail.swift            # 单帧缩略图
│   ├── KeyboardShortcutsModifier.swift # 空格/方向键监听
│   ├── PauseRemovalView.swift          # 停顿去除
│   ├── SpatialCanvasView.swift         # 画幅拼接
│   ├── DuplicatePhotoView.swift        # 重复照片检测
│   ├── DuplicateVideoView.swift        # 重复视频检测
│   ├── FileCopyView.swift              # 文件复制
│   ├── FileSearchView.swift            # 文件搜索
│   ├── MediaRepairView.swift           # 媒体修复
│   └── HelpPanelView.swift             # 帮助窗口（功能说明，需与 README 同步）
└── Services/
    ├── VideoToolkit.swift              # 读取信息、裁剪/缩放/拼接、图片与 GIF 导出
    ├── AudioVideoToolkit.swift         # 音视频合并、变速、偏移、分离
    ├── VideoScreenshotExtractor.swift  # 截图提取、质量评分、去重、保存、ZIP（未接入 UI）
    ├── PauseRemover.swift              # 静音检测与紧凑导出
    ├── SpatialCanvasService.swift      # 画布逐帧渲染、混音、MP4 导出
    ├── DuplicatePhotoScanModel.swift   # 照片扫描状态机（快速/精细）
    ├── DuplicateVideoScanModel.swift   # 视频扫描状态机（快速/精细）
    ├── SimilarPhotoClusterer.swift     # dHash+pHash 连通分量聚类
    ├── SimilarVideoClusterer.swift     # 分段指纹聚类
    ├── MediaHashCache.swift            # 照片/视频哈希提取与分片缓存
    ├── MediaRepairModel.swift          # 修复流程状态
    ├── MediaRepairService.swift        # 检测/重命名/无损 remux
    ├── FileSearchModel.swift           # 搜索状态
    ├── FinderSearchService.swift       # 递归文件名搜索 + 分组
    ├── FileHasher.swift                # SHA256 流式哈希
    ├── FolderScanner.swift             # 递归文件扫描（后台调用）
    ├── SecurityBookmarkStore.swift     # 安全范围书签
    ├── WorkManager.swift               # 任务冲突仲裁
    ├── OperationLogManager.swift       # 操作日志
    └── Infrastructure/
        ├── BaseObservableService.swift # 统一 ObservableService 基类
        ├── ServiceProtocols.swift      # 服务协议 / ProgressInfo / 错误
        └── FileOperations.swift        # 废纸篓、唯一文件 URL
```

**注意**：仓库里还有 `Services/StaticTools.swift`，但它**没有加入 Xcode target**，且与 `FileHasher.swift` / `FolderScanner.swift` / `MediaToolsUtilities.swift` 中的声明重复。修改 `StaticTools.swift` 不会影响 App；不要把它当作有效代码。

---

## 6. 功能 → 代码对照表

| 功能 | View | 核心 Service / 模型 | 关键依赖 |
|------|------|---------------------|----------|
| 宽高调整 | `VideoCropResizeView` + `CropSettingsView` / `ResizeSettingsView` / `OutputSettingsView` / `CropOverlay` | `VideoToolkit` | AVFoundation、ImageIO |
| 视频片段整合 | `VideoConcatView` | `VideoToolkit.exportConcatenated` | AVMutableComposition |
| 音视频处理 | `AudioVideoEditorView` + 4 个时间轴组件 | `AudioVideoToolkit` | AVMutableComposition |
| 批量截图 | `VideoScreenshotExtractorView` + `ThumbnailPreviewPanel` / `FrameThumbnail` | `VideoScreenshotExtractor` | AVAssetImageGenerator、TaskGroup |
| 停顿去除 | `PauseRemovalView` | `PauseRemover` | AVAssetReader / Composition |
| 画幅拼接 | `SpatialCanvasView` + `CanvasElementView` / `CanvasResizeHandles` | `SpatialCanvasToolkit` | AVAssetWriter、CVPixelBuffer |
| 重复照片检测 | `DuplicatePhotoView` + `PhotoComparisonPanel` | `DuplicatePhotoScanModel` + `SimilarPhotoClusterer` + `MediaHashCache` | CryptoKit、ImageIO |
| 重复视频检测 | `DuplicateVideoView` + `VideoComparisonPanel` | `DuplicateVideoScanModel` + `SimilarVideoClusterer` + `MediaHashCache` | AVFoundation |
| 文件复制工具 | `FileCopyView` | `FileHasher` + AVFoundation | CryptoKit |
| 文件搜索 | `FileSearchView` | `FileSearchModel` → `FinderSearchService` | FileManager、QuickLookThumbnailing/ImageIO |
| 媒体修复 | `MediaRepairView` | `MediaRepairModel` → `MediaRepair` | ImageIO、AVFoundation |

---

## 7. 写代码前的硬性约定

### 7.1 Feature View 布局模板

所有功能页统一使用（标题由 `RootView` 的 `.navigationTitle` 管理，子视图不设标题）：

```swift
ScrollView {
    VStack(alignment: .leading, spacing: 14) {
        // 内容
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
}
.frame(maxWidth: .infinity, maxHeight: .infinity)
.scrollIndicators(.visible)
.background(Color(NSColor.controlBackgroundColor))
```

- **不要**依赖 `Spacer()` 解决容器填充问题。
- 布局问题要**全面排查**相关视图，不做局部改动。

### 7.2 不要在 NavigationSplitView 详情区嵌套分栏视图

- **禁止**在详情区放 `HSplitView` / `NSSplitView`。
- 2026-10-31 的线上问题：批量截图页在详情区嵌套 `HSplitView` 且内层 `.frame(minWidth: 1000)`，打开该功能时外层导航侧边栏被挤成约 80px 的窄条（只剩残字），其他功能正常。
- 正确做法：单个外层 `ScrollView` + `HStack(alignment: .top)`，左列固定宽度、右列 `.frame(maxWidth: .infinity)`。
- 详情区内部也不要声明接近窗口最小宽度的 `minWidth`；窗口最小尺寸由 `RootView.frame(minWidth: 1000, minHeight: 700)` 统一管理。

### 7.3 ScrollView 与手势

- `ScrollView` 内**禁止**用 `.offset()` + `DragGesture` 手动平移内容。
- 需要拖拽/缩放的编辑模式（画幅拼接），**条件性移除内层 ScrollView**，避免手势竞争；浏览模式再包 ScrollView。
- 尽量避免嵌套 ScrollView；必须嵌套时限定内层尺寸并避免竞争手势。

### 7.4 图片与画布

- `Image.resizable().aspectRatio(contentMode: .fit)` 在 ZStack 中必须补 `.frame(maxWidth: .infinity, maxHeight: .infinity)` 填满容器，否则与绝对定位元素错位。
- 缩放/百分比控件的分母必须等于实际渲染尺寸，不要引入中间裁切上限。

### 7.5 AVFoundation

- `UTType("...")` 必须可选绑定或 `.compactMap { $0 }`，禁止 `!`（`public.avi` / `com.microsoft.wmv` 等在部分系统未注册）。
- 读取 `CGImage` 像素时，通过 `bitmapInfo` 检测字节序（Apple Silicon 常为 BGRA，Intel 可能为 ARGB），禁止硬编码通道顺序。
- 用 `CGContext` 重绘图片时使用标准 8bpc sRGB premultipliedLast 格式，不要直接套用源图 `bitmapInfo`。
- 视频帧质量评分使用 BT.601 Y 通道 + Sobel 3×3；质量筛选用百分位，不用跨视频绝对阈值。
- 视频帧去重使用时序滑动窗口；不要用簇锚点算法。

### 7.6 文件写入

- 写文件前检查目标是否存在，或使用 `.withoutOverwriting`；需要覆盖时明确说明。
- 自动命名使用 `原名_1.ext`、时间戳等全局唯一规则。
- 用户选择目录后，跨启动访问需通过 `SecurityBookmarkStore` 保存/解析安全书签。
- 中间结果优先留在内存，用户确认后再写盘（批量截图是典型例子）。

### 7.7 并发与错误

- 长耗时操作不得在主线程执行。
- 跨功能共享状态放 `RootView` 的 `@StateObject`。
- 禁止空 `catch`；错误信息本地化为中文。
- 任务开始/结束必须成对登记/清理 `WorkManager`。

---

## 8. 常见修改场景速查

| 你要做什么 | 需要改哪里 |
|------------|-----------|
| 新增一个功能 | `Models/ToolFeature.swift` 加 case → `RootView` 的 switch 加分支 → 新建 Feature View（套模板）→ 把新文件加入 Xcode target → 更新 README 功能表/详细说明/代码地图/对照表 → 更新 `HelpPanelView.helpFeatures` |
| 删除/重命名功能 | 同上反向操作；注意 `ToolFeature` 顺序就是侧边栏顺序 |
| 修改某个功能的算法 | 先看本文件「功能 → 代码对照表」定位 Service；算法类改动同时检查 BUG_KNOWLEDGE 对应条目 |
| 修改界面布局 | 套用 7.1 模板；涉及分栏先读 7.2；改完检查其他功能页是否受影响 |
| 修改扫描/检测流程 | `DuplicatePhotoScanModel` / `DuplicateVideoScanModel` / `MediaRepairModel`；共享状态在 `RootView` |
| 修改安装/发布 | `build.sh`；必须保持「免密码、/Applications 单一副本、无嵌套目录」 |
| 新增文件 | 在 Xcode 里加入 `MacMediaTools` target（工程是显式文件成员，漏加会编译不到） |
| 修改帮助文案 | `README.md` 与 `Features/HelpPanelView.swift` 同步 |
| 修复线上 Bug | 先读 `BUG_KNOWLEDGE.md`；修复后补一条知识条目（含场景/根因/规则/例外/来源/置信度） |

---

## 9. 验证清单（每次改动后）

### 9.1 编译

```bash
./build.sh
```

或至少：

```bash
xcodebuild -project MacMediaTools.xcodeproj -scheme MacMediaTools -configuration Release \
  -destination 'platform=macOS,arch=arm64' build
```

若 Xcode 许可未同意，`xcodebuild` 会被系统拦下，需先 `sudo xcodebuild -license accept`。

**无 Xcode 许可时的最小类型检查**（备用，不生成 App；路径按本机调整）：

```bash
SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
PLUG=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins
swiftc -typecheck -sdk "$SDK" -target arm64-apple-macosx13.0 \
  -load-plugin-library "$PLUG/libSwiftUIMacros.dylib" \
  -load-plugin-library "$PLUG/libPreviewsMacros.dylib" \
  $(find MacMediaTools -name '*.swift' -not -path '*/build/*' -not -name 'StaticTools.swift')
```

### 9.2 UI 冒烟（至少覆盖本次改动相关功能）

- 启动后侧边栏 11 个功能名称完整、宽度正常，逐个切换不出现布局跳动。
- 本次改动功能的主流程可完成（选文件 → 参数 → 执行 → 输出）。
- 进度/取消/错误提示正常；任务结束后可再次启动。

### 9.3 安装标准

- `ls /Applications | grep MacMediaTools` 只有一份 `MacMediaTools.app`。
- 不存在 `/Applications/Applications/`。
- `pgrep -fl MacMediaTools` 的进程路径是 `/Applications/MacMediaTools.app/Contents/MacOS/MacMediaTools`。
- `codesign --verify --deep --strict /Applications/MacMediaTools.app` 通过。

---

## 10. 文档维护规则（强制）

> **每次改动后都必须更新 README。** 这不是可选步骤，也不是只在“新增功能”时才做。

改动完成后按以下清单检查：

1. **功能/行为变化** → 更新「功能一览」和对应「详细说明」小节。
2. **新增/删除/重命名文件** → 更新「代码地图」。
3. **Service / 数据流 / 状态归属变化** → 更新「架构与数据流」「功能 → 代码对照表」。
4. **新增约定、踩坑、算法变化** → 更新「写代码前的硬性约定」「已知坑速览」，并同步 `BUG_KNOWLEDGE.md`。
5. **构建/安装/发布流程变化** → 更新「编译 / 运行 / 安装」。
6. **修改顶部「最后更新」日期**。

功能列表/文案变化时，同时更新 `Features/HelpPanelView.swift` 的 `helpFeatures`：

- 数量、序号、名称与 README 功能表**完全一致**；
- 顺序与 `ToolFeature.allCases`（侧边栏）一致；
- `details` 内容与 README 详细说明保持一致；
- 只改数据，不改帮助窗口的布局样式。

`AGENTS.md` 的 Step 6 与本规则同步执行。

---

## 11. 已知坑速览

完整条目（场景/根因/规则/例外/来源/置信度）见 `BUG_KNOWLEDGE.md`，这里只列最常踩的：

- **UTType 强制解包崩溃**：非标准 UTI 用 `.compactMap`。
- **像素字节序**：BGRA/ARGB 因架构而异，必须读 `bitmapInfo`。
- **质量评分阈值**：必须用视频内百分位，Sobel + Y 通道。
- **帧去重**：时序滑动窗口，不要簇锚点。
- **CGContext 格式**：用标准 sRGB premultipliedLast，不套源图格式。
- **同名文件覆盖**：`Data.write(to:)` 默认静默覆盖，先查重或保证文件名唯一。
- **ScrollView + DragGesture**：不要用 `.offset()` 拖动；编辑模式移除内层 ScrollView。
- **嵌套 SplitView**：`NavigationSplitView` 详情区不要再放 `HSplitView`，否则侧边栏被挤扁（2026-10-31 批量截图问题）。
- **布局模板**：`.frame(maxWidth: .infinity, maxHeight: .infinity)` 不能省，`Spacer()` 不是兜底。
- **安装路径**：只装 `/Applications`，不要 `~/Applications`，不要嵌套目录，不要密码。

---

## 12. 隐私声明

- 所有处理完全在本地完成。
- 不上传文件、不联网、不收集用户数据。
- 沙盒权限仅限用户主动选择的文件/目录与 Downloads。

---

## 13. 下载

最新版从 GitHub Releases 获取（macOS 13.0+，Apple Silicon / Intel）：

**👉 https://github.com/UCASRMTG5D/MacMediaTools/releases**

- 下载 `.dmg` 后打开，把 `MacMediaTools` 拖入「应用程序」即可（保持单一副本，不要拖进子文件夹）。
- 从源码编译见「2. 编译 / 运行 / 安装」。

> 应用完全本地运行，无需账号、不联网。
