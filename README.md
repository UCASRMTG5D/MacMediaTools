# MacMediaTools

**纯本地 macOS SwiftUI 多媒体工具箱** — 视频处理、重复媒体检测与文件整理，全部在本地完成。

> Apple Silicon（M 系列）优先，Intel Mac 亦可编译运行。

## 功能一览

| 功能 | 说明 |
|------|------|
| **宽高调整** | 图片/视频裁剪+尺寸调整两阶段（可跳过），可视化裁剪框+实时拉伸预览 |
| **视频片段整合** | 批量选择、拖拽排序，拼接为单一视频，支持不同分辨率自动居中/裁剪 |
| **音视频处理** | 视频与音频轨道合并、时间偏移 / 速度调整、音视频分离 |
| **批量截图** | 按时间间隔截取视频帧，支持智能质量筛选与替代帧搜索、内容去重 |
| **重复照片检测** | 递归扫描，SHA256 内容哈希精确匹配 |
| **重复视频检测** | 按时长 / 大小 / 分辨率分组匹配 |
| **文件复制工具** | 智能复制媒体文件，自动检测重复并重命名 |
| **画幅拼接** | 多媒体空间拼接：图片/视频/GIF 混拼，自由拖拽定位、8锚点缩放、单轴拉伸、裁切、逐轨混音 |
| **媒体修复** | 检测并修复图片扩展名不符、视频不兼容 QuickTime 的问题（无损修复，不转码），修复前人工逐项确认 |

## 环境要求

- macOS **13.0+**
- Xcode 15.0+（推荐最新版本）

## 编译 / 运行

```bash
git clone <repo-url>
cd MacMediaTools
xed .  # 或从 Xcode 打开 MacMediaTools.xcodeproj
```

选择 `MacMediaTools` target → Run（⌘R）

> 无外部依赖，基于系统框架 AVFoundation / AVKit / CryptoKit。

## 详细说明

### 1) 宽高调整

图片 / 视频通用的宽高处理工具：可选裁剪 → 可选尺寸调整 → 导出。

- **两阶段可跳过**：可只裁剪、只调整尺寸、或二者都做
- **裁剪**：拖拽黄色裁剪框 + 数字输入宽高（双向同步），归一化坐标，正确处理旋转元数据
- **尺寸调整**：输入目标宽高，支持拉伸 / Aspect Fit（保持比例加黑边）
- **实时拉伸预览**：开启尺寸调整后，可预览缩放后的画面效果，对比新旧分辨率
- **支持图片**：PNG / JPEG / TIFF 等常见格式，与视频共用同一界面

### 2) 视频片段整合

选择多个视频 → 列表拖拽排序 → 选择输出路径 → 开始拼接。

- 列表中显示每个视频的文件名和分辨率（宽×高）
- 自动取所有视频宽高的最大值作为默认输出分辨率
- 不同分辨率的视频自动适配：小于输出尺寸的填充黑边居中，大于的裁剪边缘保留中心
- 支持手动指定输出宽高

### 3) 音视频处理

视频轨道 + 音频轨道导入 → 速度调整 → 时间偏移 → 合并导出。

- 支持起始对齐、结束对齐、同步对齐三种轨道对齐方式
- 单独的视频分离 / 音频分离功能
- 撤销 / 重做（最多 10 步）
- 基于 `AVMutableComposition` + `AVAssetExportSession`

### 4) 批量截图

选择视频 → 设置时间范围 / 间隔 → 自动截取帧 → 批量导出截图。

- **智能质量检查**：逐帧计算清晰度评分（基于梯度分析），自动在 ±1s 范围内搜索最佳替代帧
- **内容去重**：基于 16×16 灰度感知哈希比对截图内容，相似截图只保留质量最高的一张，阈值可调（默认 15%）
- 时间间隔支持滑块拖拽与直接输入数字两种方式，实时同步
- 支持 PNG / JPEG 输出格式
- 实时进度与预计剩余时间
- 键盘快捷键（空格播放/暂停，左右箭头逐帧）
- 支持导出为 ZIP 打包
- 持久化任务状态，支持恢复

### 5) 重复照片检测

递归扫描文件夹 → SHA256 哈希 → 分组输出。

- 分块读取（1MB/块），避免大文件加载到内存
- 支持常见图片格式（jpg、png、heic、webp 等 10 种）

### 6) 重复视频检测

支持两种检测模式：

**快速模式**：按时长 / 文件大小 / 分辨率分组。
- 使用 `AVFoundation` 读取视频元数据
- 精度：时长毫秒级、大小字节级

**精细模式**：dHash 内容指纹 → 分段哈希对比 → 连通分量聚类。
- 缓存哈希指纹可加速后续检测，每部视频约 700 字节
- 支持视频对比面板，并排播放 + 同步进度条，逐帧对比验证
- 按平均相似度百分比排序聚类

### 7) 文件复制工具

智能媒体文件复制，自动检测目标路径重复。

- 图片通过 SHA256 比对判定重复
- 视频通过时长 + 分辨率比对判定重复
- 重复文件自动生成带编号的文件名

### 8) 画幅拼接

将多个图片、视频、GIF 自由拼接到一个画布上（空间维度），支持自由拖拽定位、缩放、裁切与混音导出。

- **支持混拼**：图片 / 视频 / GIF 混合拼接在同一画布
- **自由拖拽**：从媒体列表拖入画布，自由摆放位置
- **8 锚点缩放**：四角手柄等比缩放，四边手柄单轴拉伸
- **裁切框叠加**：每个元素可独立裁切有效显示区域
- **逐轨混音**：每个媒体独立调节音量（如有音轨），成品混音导出
- **导出格式**：MP4 (H.264 + AAC)

### 9) 媒体修复

检测并修复媒体文件的格式/标签问题，修复前逐项人工确认。

- **检测只读**：扫描阶段只读取文件、不修改任何内容，结果按图片 / 视频两大类分组列出
- **图片扩展名不符**：实际格式（如 WebP 内容）与扩展名（如 `.jpg`）不一致会导致 Preview 显示「已锁定」、能看不能改；修复为零画质损失的扩展名重命名
- **视频不兼容 QuickTime**：编码/封装（如 HEVC 在非常规容器、avi/mkv/flv 等）QuickTime 无法打开；修复为无损封装到 QuickTime 兼容的 MP4（不转码，拷贝音视频流）
- **检测范围**：支持选择「全部 / 仅图片 / 仅视频」
- **人工确认**：勾选需要修复的项目后点击「开始修复」才会写盘，支持全选/取消
- **支持选择文件或递归扫描整个文件夹**

## 项目结构

```
MacMediaTools/
├── MacMediaToolsApp.swift         # App 入口
├── RootView.swift                 # 侧边栏导航
├── MediaToolsUtilities.swift      # 公共工具函数
├── Models/
│   ├── ToolFeature.swift          # 功能枚举
│   └── CanvasElement.swift        # 画布元素模型
├── Components/
│   ├── OpenPanelButton.swift      # 文件选择控件
│   ├── VideoProgressSlider.swift  # 视频进度 / 范围选择滑块
│   ├── CanvasElementView.swift    # 画布元素渲染组件
│   └── CanvasResizeHandles.swift  # 8锚点缩放手柄组件
├── Services/
│   ├── VideoToolkit.swift         # 视频裁剪 / 调整 / 拼接
│   ├── AudioVideoToolkit.swift    # 音视频合成 / 分离
│   ├── FileHasher.swift           # SHA256 流式哈希
│   ├── FolderScanner.swift        # 递归文件扫描
│   ├── DuplicateVideoScanModel.swift # 重复视频扫描引擎
│   ├── VideoHashCache.swift       # 视频哈希缓存
│   ├── SimilarVideoClusterer.swift # dHash 内容指纹聚类
│   ├── SpatialCanvasService.swift # 画幅拼接合成导出
│   ├── WorkManager.swift          # 工作队列管理
│   ├── OperationLogManager.swift  # 操作日志管理
│   └── VideoScreenshotExtractor.swift # 批量截图引擎
├── Components/
│   ├── OpenPanelButton.swift      # 文件选择控件
│   ├── VideoProgressSlider.swift  # 视频进度 / 范围选择滑块
│   └── VideoComparisonPanel.swift # 视频并排对比播放器
└── Features/
    ├── VideoCropResizeView.swift  # 宽高调整（图片+视频裁剪/调整）
    ├── VideoConcatView.swift      # 视频片段整合
    ├── AudioVideoEditorView.swift # 音视频编辑器
    ├── VideoScreenshotExtractorView.swift # 批量截图界面
    ├── DuplicatePhotoView.swift   # 重复照片检测
    ├── DuplicateVideoView.swift   # 重复视频检测（快速+精细模式）
    ├── FileCopyView.swift         # 文件复制工具
    ├── SpatialCanvasView.swift    # 画幅拼接主视图
    └── HelpPanelView.swift        # 帮助说明
```

## 技术栈

| 组件 | 技术 |
|------|------|
| UI | SwiftUI + NavigationSplitView |
| 视频处理 | AVFoundation / AVKit |
| 哈希 | CryptoKit (SHA256) |
| 并发 | Swift Async/Await, Actor |

## 隐私声明

- **所有处理完全在本地完成**
- 不上传文件、不联网
- 不收集用户数据

## 下载 / Download

最新版从 GitHub Releases 获取（macOS 13.0+，Apple Silicon / Intel 通用）：

**👉 https://github.com/UCASRMTG5D/MacMediaTools/releases**

- 下载 `.dmg` / `.pkg` 后拖入「应用程序」即可使用
- 安装包已用 **Developer ID 签名 + Apple 公证**，可直接打开，无 Gatekeeper 拦截
- 如需从源码自行编译，见上方「编译 / 运行」

> 应用完全本地运行，无需账号、不联网。
