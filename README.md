# MacMediaTools

**纯本地 macOS SwiftUI 多媒体工具箱** — 视频处理、重复媒体检测，全部在本地完成。

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
| **重复媒体综合检测** | 统一检测照片与视频重复，支持类型筛选与缩略图预览 |
| **文件复制工具** | 智能复制媒体文件，自动检测重复并重命名 |

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

按时长 / 文件大小 / 分辨率分组。

- 使用 `AVFoundation` 读取视频元数据
- 精度：时长毫秒级、大小字节级

### 7) 重复媒体综合检测

统一检测照片（SHA256）和视频（特征匹配），支持：

- 按类型筛选（全部 / 仅照片 / 仅视频）
- 缩略图预览（系统图标）
- 匹配原因描述
- 分组管理，支持删除操作

### 8) 文件复制工具

智能媒体文件复制，自动检测目标路径重复。

- 图片通过 SHA256 比对判定重复
- 视频通过时长 + 分辨率比对判定重复
- 重复文件自动生成带编号的文件名

## 项目结构

```
MacMediaTools/
├── MacMediaToolsApp.swift         # App 入口
├── RootView.swift                 # 侧边栏导航
├── MediaToolsUtilities.swift      # 公共工具函数
├── Models/
│   └── ToolFeature.swift          # 功能枚举
├── Components/
│   ├── OpenPanelButton.swift      # 文件选择控件
│   └── VideoProgressSlider.swift  # 视频进度 / 范围选择滑块
├── Services/
│   ├── VideoToolkit.swift         # 视频裁剪 / 调整 / 拼接
│   ├── AudioVideoToolkit.swift    # 音视频合成 / 分离
│   ├── FileHasher.swift           # SHA256 流式哈希
│   ├── FolderScanner.swift        # 递归文件扫描
│   ├── DuplicateDetector.swift    # 重复媒体检测（actor）
│   ├── OperationLogManager.swift  # 操作日志管理
│   └── VideoScreenshotExtractor.swift # 批量截图引擎
└── Features/
    ├── VideoCropResizeView.swift  # 宽高调整（图片+视频裁剪/调整）
    ├── CropOverlay.swift          # 裁剪框拖拽组件
    ├── VideoConcatView.swift      # 视频拼接
    ├── AudioVideoEditorView.swift # 音视频编辑器
    ├── VideoScreenshotExtractorView.swift # 批量截图界面
    ├── DuplicatePhotoView.swift   # 重复照片检测
    ├── DuplicateVideoView.swift   # 重复视频检测
    ├── DuplicateMediaView.swift   # 综合重复检测
    └── FileCopyView.swift         # 文件复制工具
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
