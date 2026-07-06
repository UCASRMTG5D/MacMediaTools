# Bug Knowledge Base

> 从 bug-reports/ 复盘文档中提炼的可复用经验。
> AI 在写代码前应读取此文件，避免重复踩坑。
> 每条经验都标注了精确场景、限制条件和置信度。
> 更新于: 2026-07-06 09:00

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
- [osascript](#osascript)

### 按模式分类
- [nil-safety](#nil-safety)
- [像素格式](#像素格式)
- [文件安全](#文件安全)
- [算法选择](#算法选择)
- [架构设计](#架构设计)
- [自动化部署](#自动化部署)
- [布局约束](#布局约束)

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

### CGContext bitmapInfo：禁止直接使用源图片像素格式

- **场景**：`CGImage` 缩放/重绘时通过 `CGContext` 绘制，使用源图片的 `bitmapInfo` 和 `bitsPerComponent` 创建上下文。适用于所有 `scaleCGImageStatic` 及类似的图片处理代码。
- **根因**：`CGContext(data:width:height:bitsPerComponent:bytesPerRow:space:bitmapInfo:)` 只支持有限的像素格式组合。JPEG 图片的 `alphaInfo` 为 `.none`（=0），在 RGB 色彩空间下不被支持；非预乘 Alpha（`.last`/`.first`）和浮点分量（`.floatComponents`）同样不被支持。直接使用 `image.bitmapInfo` 会导致 `CGContext` 创建失败返回 nil，抛"缩放失败"。
- **规则**：创建 CGContext 时必须使用**已知兼容的标准像素格式**，不能直接使用源图片的 bitmapInfo。推荐固定使用 8bpc sRGB premultipliedLast（`CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Host.rawValue`），CoreGraphics 在 `ctx.draw()` 时会自动转换源图格式。
- **例外**：若确定源图来自固定设备（如同一台摄像机的 8bpc 视频帧），可以直接使用源图 bitmapInfo。
- **标签**：`media-processing` `coregraphics` `nil-safety`
- **来源**：bug-report-20260706-image-crop-resize-bugs
- **置信度**：high

---

### Image.aspectRatio 在 ZStack 中的布局需要显式填满容器

- **场景**：在 `ZStack` 中使用 `Image.resizable().aspectRatio(contentMode: .fit)` 与绝对定位（`.position()`）的元素叠加时。适用于所有裁剪框叠加图片的场景。
- **根因**：`.aspectRatio(contentMode: .fit)` 会约束 Image 视图的实际尺寸为**适配容器后的 fitted 尺寸**，而非填满容器。配合 `ZStack(alignment: .topLeading)` 时，Image 视图被放置于左上角，而绝对定位的叠加元素（如裁剪框）位于容器中心，两者错位。
- **规则**：在使用 `.aspectRatio()` 约束的 Image 上必须加 `.frame(maxWidth: .infinity, maxHeight: .infinity)` 强制视图填满容器，或改用 `.aspectRatio(contentMode: .fill)` 配合 `.clipped()`。
- **例外**：`VideoPlayer` 没有 `.aspectRatio()` 约束，默认填满容器，不受此问题影响。
- **标签**：`ui` `swiftui`
- **来源**：bug-report-20260706-image-crop-resize-bugs
- **置信度**：high