# Bug Knowledge Base

> 从 bug-reports/ 复盘文档中提炼的可复用经验。
> AI 在写代码前应读取此文件，避免重复踩坑。
> 每条经验都标注了精确场景、限制条件和置信度。
> 更新于: 2026-07-10 14:00

---

## 目录

### 按模块分类
- [media-processing](#media-processing)
- [ui](#ui)
- [build-deploy](#build-deploy)
- [file-io](#file-io)

### 按技术分类
- [avfoundation](#avfoundation)
- [swiftui](#swiftui)
- [xcodebuild](#xcodebuild)
- [file-manager](#file-manager)
- [coregraphics](#coregraphics)
- [osascript](#osascript)

### 按模式分类
- [nil-safety](#nil-safety)
- [像素格式](#像素格式)
- [文件安全](#文件安全)
- [算法选择](#算法选择)
- [架构设计](#架构设计)
- [自动化部署](#自动化部署)
- [布局约束](#布局约束)
- [坐标变换](#坐标变换)
- [手势](#手势)

---

## media-processing

### UTType 安全：禁止强制解包动态 UTI

- **场景**：任何调用 `UTType("...")` 并传入非标准 UTI 字符串的代码。标准 UTI（如 `.movie`、`.mpeg4Movie`、`.quickTimeMovie`、`.png`、`.jpeg`）是安全的，但 `public.avi`、`public.flv`、`com.microsoft.wmv` 等非标准 UTI 在某些 macOS 版本上未注册，返回 nil。
- **根因**：`UTType("public.flv")` 和 `UTType("com.microsoft.wmv")` 在部分 macOS 系统不是已注册 UTI，强制解包 `!` 触发 `EXC_BREAKPOINT (SIGTRAP)`。此类问题不会在编译时暴露，只能在运行时触发。
- **规则**：对所有 `UTType("...")` 调用必须使用可选绑定或 `.compactMap { $0 }`，禁止使用 `!` 强制解包。模式：`.compactMap { UTType($0) }`。
- **例外**：使用 `UTType` 静态属性（如 `.movie`、`.mpeg4Movie`、`.quickTimeMovie`、`.png`、`.jpeg` 等系统内置 UTI）不需要此保护，因为这些永远非 nil。
- **来源**：bug-report-20260702-150200-crash-switch-feature
- **置信度**：high
- **标签**：`media-processing` `avfoundation` `nil-safety`

---

### 像素格式字节序：AVFoundation 返回格式因架构而异

- **场景**：使用 `AVAssetImageGenerator.copyCGImage()` 读取视频帧像素数据，手动计算帧间差异或图像质量评分时。适用于所有使用 AVFoundation 的视频处理代码。
- **根因**：Apple Silicon (arm64) 返回 **BGRA** 格式，Intel Mac (x86_64) 返回 **ARGB** 格式。代码假设统一格式（如假设第 0 字节是 R），实际读到 Alpha 通道（值 = 255），导致灰度基线固定，帧间差异趋近于 0。
- **规则**：必须通过 `bitmapInfo` 检测像素格式字节序，不能硬编码通道顺序。参考实现：检查 `pixelBuffer.bitmapInfo` 中的 `kCGBitmapByteOrder32Little` 标志，动态选择通道映射。
- **例外**：仅读取单个帧的像素值而不做帧间比较或通道逐位计算时，不需要此处理。使用 `NSImage` / `CGImage` 的 UIKit/SwiftUI 上层 API（如直接显示图片）也不受影响。
- **来源**：bug-report-20260702-184520-screenshot-count-mismatch
- **置信度**：high
- **标签**：`media-processing` `avfoundation` `像素格式`
- **关联条目**：见「CGContext bitmapInfo：禁止直接使用源图片像素格式」— 同类问题：底层 API 的像素格式不可假设，必须检测或标准化。

---

### 图像质量评分：绝对阈值不可跨视频通用

- **场景**：需要对视频帧进行无参考质量评分（sharpness/blur detection），以筛选高质量帧或替换模糊帧。适用于所有视频帧质量评估代码。
- **根因**：所有无参考图像质量评分方法（梯度分析、Sobel、Laplacian、FFT 等）都对视频内容敏感。同一方法在不同视频（不同场景、光照、设备）上输出的分数相差 2-3 个数量级。设定绝对阈值（如 `score > 0.85`）无法跨视频通用。文献确认此结论（OpenCV focus measure study + FFmpeg blurdetect + 多篇综述）。
- **规则**：
  1. 质量评分必须基于视频内相对排名（**百分位**），而非跨视频绝对阈值。
  2. 推荐方法：**Sobel 3×3 核 + BT.601 Y 通道亮度计算**（消除 RGB 色彩噪声）。
     - Y = 0.299R + 0.587G + 0.114B
     - Gx: [[-1, 0, +1], [-2, 0, +2], [-1, 0, +1]]
     - Gy: [[-1, -2, -1], [0, 0, 0], [+1, +2, +1]]
     - magnitude = sqrt(Gx² + Gy²)，score = mean(magnitude)
  3. 质量替换逻辑（±1s 搜索最佳帧）不应依赖阈值触发，应**始终执行**。
  4. 阈值 slider 仅用于最终筛选的百分位截断，不参与替换决策。
- **例外**：如果视频内容类型已知且固定（如固定机位的监控视频、扫描文档），可以使用经过标定的绝对阈值。
- **来源**：bug-report-20260702-184520-screenshot-count-mismatch
- **置信度**：high

---

### 视频截图去重：簇锚点算法不适用于视频帧

- **场景**：对连续视频帧进行内容去重，以移除高度相似的帧。适用于批量截图功能中的去重逻辑。
- **根因**：簇锚点去重（每帧与簇首帧对比，diff < 阈值即归入同一簇）在视频帧场景下会导致几乎所有帧被归入 1-2 个簇，每簇只保留 1 帧，输出数量远低于预期。
- **规则**：视频帧去重必须使用**时序滑动窗口**算法。窗口内的帧只与**上一个保留帧**比较差异，而非与任意锚点帧比较。差异阈值要支持细粒度调节（步长 0.01，范围 1%–4%）。
- **例外**：对于在时间上不连续的帧集合（如不同视频文件提取的帧混合），可以使用簇锚点算法。
- **来源**：bug-report-20260702-184520-screenshot-count-mismatch
- **置信度**：high

---

### 纯内存 + 按需保存：数据筛选不应依赖磁盘写入

- **场景**：处理中间数据需要经过多维度筛选，最终用户确认后再持久化的场景。适用于数据管道的架构设计。
- **根因**：早期设计在提取阶段直接写入磁盘，去重/质量筛选在写盘之后再做，导致磁盘文件数与 UI 显示数不一致、磁盘浪费、用户无法预览效果。此外 `Data.write(to:)` 同名文件静默覆盖加剧了此问题。
- **规则**：数据处理管道应遵循：**提取（全量内存）→ 多维度筛选（内存中计算多种结果）→ UI 预览 → 用户确认保存**。提取阶段不做任何磁盘写入，`saveFrames` 等写盘 API 只在用户确认后调用。
- **例外**：处理的数据量大到无法放入内存（如 4K 视频全帧提取、大型数据集）时，可改为临时文件 + 清理机制。
- **来源**：bug-report-20260702-184520-screenshot-count-mismatch
- **置信度**：high

---

### Sobel 质量评分：RGB→Y 通道 + 替换触发解耦

- **场景**：使用裸像素差分梯度计算帧质量分数，且替换逻辑依赖阈值触发的代码。
- **根因**：
  1. RGB 三通道各自差分再 sqrt → 色彩噪声放大。
  2. 裸像素差分（等价 [1,-1] 核）抗噪差，边缘检测精度低。
  3. 质量替换逻辑依赖 `qualityScore < qualityThreshold` 触发，导致阈值设置不合理时替换完全失效。
- **规则**：
  1. 使用 BT.601 Y 通道（单通道）消除色彩噪声。
  2. 使用 Sobel 3×3 核对 Y 通道做边缘响应（较 [1,-1] 核抗噪更好）。
  3. 质量替换应始终搜索 ±1s 最佳帧，**不依赖阈值触发**。
- **例外**：无。此模式在所有帧替换场景中应统一。
- **来源**：bug-report-20260702-184520-screenshot-count-mismatch
- **置信度**：high

---

### CGContext bitmapInfo：禁止直接使用源图片像素格式

- **场景**：`CGImage` 缩放/重绘时通过 `CGContext` 绘制，使用源图片的 `bitmapInfo` 和 `bitsPerComponent` 创建上下文。适用于所有 `scaleCGImageStatic` 及类似的图片处理代码。
- **根因**：`CGContext(data:width:height:bitsPerComponent:bytesPerRow:space:bitmapInfo:)` 只支持有限的像素格式组合。JPEG 图片的 `alphaInfo` 为 `.none`（=0），在 RGB 色彩空间下不被支持；非预乘 Alpha（`.last`/`.first`）和浮点分量（`.floatComponents`）同样不被支持。直接使用 `image.bitmapInfo` 会导致 `CGContext` 创建失败返回 nil，抛"缩放失败"。
- **规则**：创建 CGContext 时必须使用**已知兼容的标准像素格式**，不能直接使用源图片的 bitmapInfo。推荐固定使用 8bpc sRGB premultipliedLast（`CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Host.rawValue`），CoreGraphics 在 `ctx.draw()` 时会自动转换源图格式。
- **例外**：若确定源图来自固定设备（如同一台摄像机的 8bpc 视频帧），可以直接使用源图 bitmapInfo。
- **标签**：`media-processing` `coregraphics` `像素格式`
- **来源**：bug-report-20260706-crop-resize-canvas-all (Bug 1/3/4)
- **置信度**：high
- **关联条目**：见「像素格式字节序：AVFoundation 返回格式因架构而异」— 同类问题：底层 API 的像素格式不可假设，必须检测或标准化。

---

## ui

### NavigationSplitView 布局：Feature View 必须约束填充 Detail 区域

- **场景**：使用 `NavigationSplitView` 的 macOS SwiftUI 应用，所有 Feature View 都需要正确填充 Detail 区域。适用于任何被放置在 NavigationSplitView 详情侧的子视图。
- **根因**：NavigationSplitView 的 Detail 侧需要子视图用 `.frame(maxWidth: .infinity, maxHeight: .infinity)` 声明「我要填满可用空间」。缺失此约束时，系统无法确定视图尺寸，导致布局算法异常：内容被推到顶部（上浮）、侧边栏位置漂移。
- **规则**：所有 Feature View 必须使用统一布局模板：
  ```swift
  ScrollView {
      VStack(alignment: .leading, spacing: 14) {
          // 具体功能内容
      }
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
  }
  .frame(maxWidth: .infinity, maxHeight: .infinity)
  .scrollIndicators(.visible)
  .background(Color(NSColor.controlBackgroundColor))
  ```
  标题统一由 `.navigationTitle()` 在 RootView 管理，不在子视图中设置。
- **例外**：不使用 NavigationSplitView 的独立窗口或 modal 视图不需要此约束。
- **来源**：MacMediaTools UI 上浮-侧边栏异常问题排查记录
- **置信度**：high

---

### Spacer 不是布局救命稻草

- **场景**：在 SwiftUI 布局异常时尝试用 `Spacer()` 推动内容。适用于任何需要填充空间的布局场景。
- **根因**：`Spacer()` 在容器约束缺失时行为不可预测。它只在父视图明确确定尺寸后才会正确分配弹性空间。当父视图本身缺乏 `frame(maxHeight: .infinity)` 约束时，Spacer 无法工作，甚至加剧布局异常。
- **规则**：不要依赖 `Spacer()` 解决容器填充问题。始终先用 `.frame(maxWidth: .infinity, maxHeight: .infinity)` 确保父视图填充容器，再用 Spacer 做内部弹性分配。
- **例外**：在已知容器尺寸确定的场景（如固定高度 HStack、对话框内部）可以使用 Spacer。
- **来源**：MacMediaTools UI 上浮-侧边栏异常问题排查记录
- **置信度**：high

---

### 局部布局修改可能让问题更糟

- **场景**：在代码库中部分视图有完整布局约束、部分没有时，仅修改其中一部分。
- **根因**：在一个不一致的系统里只改一部分，会放大整体不一致性。NavigationSplitView 的布局算法在多视图间切换时出现更明显的跳动，反而感觉问题更严重。
- **规则**：布局问题必须**全面排查**所有相关视图，统一采用同一套布局模板。不做「先改几个看看效果」的部分修改。
- **例外**：视图之间没有切换关联（如独立页面、不共享同一 NavigationSplitView）时可以局部修改。
- **来源**：MacMediaTools UI 上浮-侧边栏异常问题排查记录
- **置信度**：high

---

## build-deploy

### xcodebuild 安装路径：禁止降级到 ~/Applications

- **场景**：xcode-build-install skill 执行到最后一步，将 build 产物复制到 /Applications 时。仅适用于本地 macOS app 的自动化安装流程。
- **根因**：skill 指令模糊（「Request elevated filesystem permission」），Agent 在 `sudo` 因非交互环境失败后，静默降级安装到 `~/Applications/`。但 LaunchServices 可能无法正确注册 app，不符合 skill 合同要求。
- **规则**：
  1. 安装到 `/Applications` 的路径是**硬性要求**，不允许降级到 `~/Applications/` 或任何其他路径。
  2. 首选方法：合并为一个 `osascript` 调用完成删除 + 复制，只弹一次密码对话框：
     ```bash
     osascript -e "do shell script \"rm -rf '/Applications/<AppName>.app' && cp -R '$BUILT_APP_DIR/<AppName>.app' '/Applications/'\" with administrator privileges"
     ```
  3. 后备方法：`sudo` 一行命令（仅交互式环境可用）：
     ```bash
     sudo rm -rf /Applications/<AppName>.app && sudo cp -R "$BUILT_APP_DIR/<AppName>.app" /Applications/
     ```
  4. 两者都失败时，打印精确的手动命令，**不自动降级**。
  5. 安装后必须验证 bundle version 和 modify time 匹配。
- **例外**：无。/Applications 是唯一的合法安装路径。
- **来源**：bug-report-20260702-151500-xcodebuild-install-evolution
- **置信度**：high

---

### BUILT_APP_DIR 必须显式定义

- **场景**：xcode-build-install skill 中需要在 xcodebuild 后定位 built app 的路径。
- **根因**：`BUILT_APP_DIR` 变量在 SKILL.md 中使用了但从未在步骤中显式赋值，Agent 只能隐式推导路径，可能解析到错误位置。
- **规则**：在 `xcodebuild` 命令后立即显式定义 `BUILT_APP_DIR`：
  ```bash
  BUILT_APP_DIR=$(find ./build/DerivedData -path "*/Products/Release/*.app" -type d -maxdepth 5 2>/dev/null | head -1)
  ```
  或直接指向已知路径：`./build/DerivedData/Build/Products/Release`。
- **例外**：无。任何时候使用 `BUILT_APP_DIR`，必须先显式赋值。
- **来源**：bug-report-20260702-151500-xcodebuild-install-evolution
- **置信度**：high

---

### osascript 密码提权：一次调用完成所有操作

- **场景**：使用 `osascript` 请求管理员权限执行多个 shell 命令（如先删除旧文件再复制新文件）。
- **根因**：每个独立的 `osascript` 调用都需要一次管理员密码认证。分开调用（一个删除 + 一个复制）会触发**两次密码对话框**，用户体验差。
- **规则**：将所有需要提权的 shell 命令合并到一个 `osascript` 调用中，用 `&&` 连接：
  ```bash
  osascript -e "do shell script \"rm -rf '/Applications/App.app' && cp -R '/path/App.app' '/Applications/'\" with administrator privileges"
  ```
  一次提权，完成所有操作。
- **例外**：各操作必须独立授权时（场景极少），可以分开调用。
- **来源**：bug-report-20260702-151500-xcodebuild-install-evolution
- **置信度**：high

---

### 安装后验证：比较 built app 和 installed app 的版本/时间

- **场景**：任何自动将 build 产物安装到目标目录的流程（cp / rsync / osascript 安装后）。
- **根因**：安装后仅检查文件存在，不验证安装的 app 与编译产物是否版本一致/时间一致，导致可能安装的是缓存旧版。
- **规则**：安装后必须验证：
  1. 比较 `CFBundleVersion`（`defaults read /Applications/App.app/Contents/Info.plist CFBundleVersion`）
  2. 比较 `mtime`（`stat -f %m` 比较 built 和 installed 的修改时间）
  3. `built >= installed` 为通过，否则报错提示重新安装。
- **例外**：非 app bundle 类型的文件安装（如 dylib、脚本、配置文件）不需要此验证。
- **来源**：bug-report-20260702-151500-xcodebuild-install-evolution
- **置信度**：high

---

## file-io

### Data.write(to:) 静默覆盖同名文件

- **场景**：任何调用 `Data.write(to:options:)` 写入文件的代码，尤其是文件名由变量动态生成的场景（如时间戳、帧序号、哈希值）。
- **根因**：`Data.write(to:)` 默认行为是直接**覆盖**已存在的文件，不检查、不报错、不抛异常。当多个数据条目收敛到同一文件名时，写入静默覆盖，磁盘文件数少于预期。
- **规则**：在写入前必须检查文件是否已存在（`FileManager.default.fileExists(atPath:)`），或使用 `Data.write(to:options:.withoutOverwriting)` 让系统在冲突时抛错。更推荐：确保文件名**全局唯一**（如使用原始数据标识而非处理后结果）。
- **例外**：明确预期是覆盖写入的场景（如缓存更新、临时文件刷新、日志轮转）不需要此检查。
- **来源**：bug-report-20260702-184520-screenshot-count-mismatch
- **置信度**：high

---

### ExFAT 文件"已锁定"排查：格式与扩展名一致性优先于 xattr

- **场景**：ExFAT 外置卷上的媒体文件在 Preview 中显示"已锁定"（标题栏），无法编辑保存，但 Finder 无锁图标、Terminal 操作正常。适用于所有 ExFAT 卷上文件行为异常的排查。
- **根因**：文件实际格式与扩展名不一致（如 WebP 内容但扩展名为 `.jpg`）。Preview 根据扩展名选择编解码器：`.jpg` → JPEG 编解码器 → 无法编辑 WebP 内容 → 显示"已锁定"（实质是"当前格式无法编辑保存"）。非文件系统层面的锁定。
- **规则**：
  1. 排查顺序：**先 `file` 命令验证实际格式**，再查 xattr/权限/ACL
  2. macOS 的 `sips -g format` 可快速检测文件真实编码格式
  3. 扩展名与实际格式不匹配时，Preview/viewer 可能能显示但不能编辑保存
  4. `xattr -c` / `._` 侧车文件清理通常不是这类问题的解决方案
- **例外**：如果文件格式与扩展名一致但仍显示"已锁定"，则需排查 xattr（`com.apple.macl`、`com.apple.quarantine`）、Finder flags（`chflags`）、权限等文件系统层面原因。
- **标签**：`file-io` `exfat` `investigation-methodology`
- **来源**：ExFAT_Locked_Files_Deep_Dive.md (Chapter 9)
- **置信度**：high

---

### Image.aspectRatio 在 ZStack 中的布局需要显式填满容器

- **场景**：在 `ZStack` 中使用 `Image.resizable().aspectRatio(contentMode: .fit)` 与绝对定位（`.position()`）的元素叠加时。适用于所有裁剪框叠加图片的场景。
- **根因**：`.aspectRatio(contentMode: .fit)` 会约束 Image 视图的实际尺寸为**适配容器后的 fitted 尺寸**，而非填满容器。配合 `ZStack(alignment: .topLeading)` 时，Image 视图被放置于左上角，而绝对定位的叠加元素（如裁剪框）位于容器中心，两者错位。
- **规则**：在使用 `.aspectRatio()` 约束的 Image 上必须加 `.frame(maxWidth: .infinity, maxHeight: .infinity)` 强制视图填满容器，或改用 `.aspectRatio(contentMode: .fill)` 配合 `.clipped()`。
- **例外**：`VideoPlayer` 没有 `.aspectRatio()` 约束，默认填满容器，不受此问题影响。
- **标签**：`ui` `swiftui`
- **来源**：bug-report-20260706-crop-resize-canvas-all (Bug 1/3/4)
- **置信度**：high

---

### ScrollView 内禁止使用 .offset() 做手动拖动：offset 会推出可视区

- **场景**：在 `ScrollView` 内部对子视图使用 `.offset()` + `DragGesture` 实现手动拖动/平移。适用于所有需要在 ScrollView 内移动内容的场景。
- **根因**：`.offset()` 改变的是视图的渲染位移，不影响 ScrollView 的 contentOffset。ScrollView 的可视区起点始终从 (0,0) 开始显示内容，不受子视图 `.offset()` 影响。如果 offset 推到负值，内容被推到 ScrollView 可视区之外，用户看不到。DragGesture 改动的偏移值与 ScrollView 的滚动机制是两套独立的坐标系统，不会自动同步。
- **规则**：ScrollView 内**永远不要**用 `.offset()` + `DragGesture` 做手动拖动。ScrollView 本身就支持 trackpad/鼠标滚轮翻阅内容——这是它的核心职责。超大内容直接放进 ScrollView，由 ScrollView 的滚动机制处理浏览。
- **例外**：如需微调元素位置（非拖动整个画布），且 offset 范围在可视区内（如元素对齐微调），可以使用 `.offset()`。但不要与 ScrollView 的滚动功能竞争。
- **标签**：`ui` `swiftui` `布局约束`
- **来源**：bug-report-20260706-crop-resize-canvas-all (Spatial Round 1)
- **置信度**：high

---

### 嵌套 ScrollView 手势冲突：内层可能被外层拦截

- **场景**：在 SwiftUI 布局中存在两层或以上的 ScrollView（如外层包裹整页内容，内层包裹画布/列表）。适用于所有嵌套 ScrollView 的 SwiftUI 布局。
- **根因**：SwiftUI 默认将滚动手势路由给最外层的 ScrollView。当用户在内层 ScrollView 区域滚动时，手势可能被外层捕获，导致内层 ScrollView 不可滚动或跳动。
- **规则**：
  1. 尽量避免嵌套 ScrollView。优先使用单层 ScrollView 处理所有滚动需求。
  2. 如必须嵌套（例如外层满足模板要求，内层处理独立滚动区），给内层 ScrollView 设置严格 frame 约束（`.frame(maxWidth: .infinity, minHeight: N, maxHeight: N)`）以明确其可视区域边界。
  3. 内外层使用不同滚动轴：外层默认垂直滚动，内层使用 `[.horizontal, .vertical]`——SwiftUI 在双轴 ScrollView 上更可能正确路由手势。
  4. 不要在嵌套的 ScrollView 内添加竞争手势（如 DragGesture）——这会进一步破坏手势优先级。
- **例外**：当内层 ScrollView 尺寸严格限制且无竞争手势时，嵌套结构通常稳定。因项目模板要求无法去掉外层 ScrollView 时，此例外适用。
- **标签**：`ui` `swiftui` `布局约束`
- **来源**：bug-report-20260706-crop-resize-canvas-all (Spatial Round 1)
- **置信度**：high

---

### 缩放比例分母必须与实际渲染尺寸一致：中间裁切会导致百分比错位

- **场景**：zoom/slider 控件的百分比标度显示与实际视觉缩放尺寸不一致。适用于所有包含缩放控件 + preview 渲染的场景。
- **根因**：`canvasScale` 作用的底层尺寸（`canvasDisplaySize`）经过裁切（如 760px 上限），不是用户设置的实际 canvas 尺寸（1920×1080）。slider 显示 200% (`canvasScale = 2.0`) 但实际渲染为 `760*2.0 / 1920 = 79%` 的真实尺寸，造成感知错位。中间转换尺寸改变了分数的分母。
- **规则**：缩放控件的百分比 `canvasScale * 100` 必须直接对应实际渲染尺寸的倍数。`canvasDisplaySize` 不能引入裁切或上限——必须等于 `canvasSize`。百分比 = 渲染像素 / 真实canvas尺寸 × 100。
- **例外**：如果 zoom 百分比需要表达"相对于视口"的缩放（而非相对于原始 canvas），需明确在 UI 上标注，且 slider 的 in: range 要重新计算。
- **标签**：`ui` `swiftui` `架构设计`
- **来源**：bug-report-20260706-crop-resize-canvas-all (Spatial Round 1)
- **置信度**：high

---

### 缩放坐标变换：CanvasResizeHandles 必须应用 canvasScale

- **场景**：`CanvasResizeHandles`（8锚点缩放手柄）叠加在缩放后的画布 ZStack 上使用 `.position()` 定位手柄并响应 `DragGesture`。适用于所有带 zoom/scaling 的画布编辑器。
- **根因**：`CanvasResizeHandles` 使用 `element.canvasFrame`（逻辑坐标系，如 1920×1080）计算手柄位置，而 ZStack 被 `canvasScale` 缩放（如 0.5× → 960×540），且 `.coordinateSpace(.named("canvas"))` 绑定到缩放后的 frame。当 `canvasScale ≠ 1.0` 时：
  1. 手柄 `.position()` 坐标超出坐标空间范围（如 1920px → 960px 空间中跑到可见区外）
  2. `DragGesture` 的 `translation` 在缩放坐标系中，直接应用于逻辑坐标导致效果与视觉不一致
  3. `canvasScale` 参数未传入 `CanvasResizeHandles`，无法感知缩放状态
- **规则**：
  1. `CanvasResizeHandles` 必须接收 `canvasScale` 参数（`let canvasScale: CGFloat`）
  2. 手柄位置计算（`position(for:in:)`）中 frame 坐标必须乘以 `canvasScale`：`frame.maxX * canvasScale`
  3. 拖拽增量必须除以 `canvasScale` 映射回逻辑坐标：`translation.width / canvasScale`
- **例外**：如果画布始终保持 `canvasScale = 1.0`（不可缩放），则不需要此变换。但任何支持 zoom 的画布编辑器都必须应用。
- **标签**：`ui` `swiftui` `坐标变换`
- **来源**：bug-report-20260706-crop-resize-canvas-all (Spatial Round 5)
- **置信度**：high

---

### 嵌套 ScrollView 中的 DragGesture：条件性移除内层 ScrollView

- **场景**：嵌套 ScrollView（外层模板 ScrollView + 内层画布 ScrollView）内需要对子视图使用 DragGesture（拖拽移动、缩放锚点、裁剪端点）。适用于所有嵌套 ScrollView + 编辑交互的场景。
- **根因**：`.highPriorityGesture()` 虽然能提升 DragGesture 优先级，但在嵌套 ScrollView 结构中无法保证完全压制内层 ScrollView 的滚动。SwiftUI 的手势路由在多层 ScrollView 中仍可能将滚动手势优先分配给 ScrollView。规则叠加是缓解而非根治。
- **规则**：
  1. 需要 DragGesture 的编辑模式下，**条件性移除内层 ScrollView**——画布内容直接渲染在 plain 父视图中，DragGesture 无需与滚动竞争
  2. 仅浏览模式下保留 ScrollView 包裹支持滚动
  3. 实现方式：`Group { if needsDrag { plainView } else { ScrollView { content } } }`，`needsDrag` 由编辑模式状态决定
  4. 条件移除 ScrollView 后，DragGesture 仍使用 `.highPriorityGesture()` 作为额外保障
- **例外**：如果画布尺寸始终适配视口（不会超出可见区域），可以保留 ScrollView + `.highPriorityGesture()` 方案。但任何可能缩放导致画布超出视口的编辑器都应采用条件移除策略。
- **标签**：`ui` `swiftui` `布局约束` `手势`
- **来源**：bug-report-20260706-crop-resize-canvas-all (Spatial Round 6)
- **置信度**：high