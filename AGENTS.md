# MacMediaTools — Agent Guide

## Project Overview

macOS SwiftUI(Swift) 多媒体工具箱（纯本地，无外部依赖），使用 AVFoundation/AVKit/CryptoKit。

## CRITICAL: Read Bug Knowledge Before Coding

**Before making ANY code changes, you MUST read `BUG_KNOWLEDGE.md` to learn from past bugs and avoid reintroducing known issues.**

The knowledge base is organized by module (media-processing, ui, build-deploy, file-io) and each entry includes precise scene, root cause, rules, and exceptions. Read the sections relevant to the code you're about to change.

---

## 一、架构规范 (Architecture Standards)

### 1.1 项目目录结构

```
MacMediaTools/
├── MacMediaToolsApp.swift          # @main 入口
├── RootView.swift                  # NavigationSplitView 导航
├── MediaToolsUtilities.swift       # 全局工具函数/扩展
├── Models/                         # 数据模型/枚举
│   └── ToolFeature.swift           # 功能枚举 (CaseIterable)
├── Services/                       # 业务逻辑层 (无 UI 依赖)
│   ├── VideoToolkit.swift
│   ├── AudioVideoToolkit.swift
│   ├── FileHasher.swift
│   ├── FolderScanner.swift
│   ├── DuplicateVideoScanModel.swift
│   ├── VideoHashCache.swift
│   ├── SimilarVideoClusterer.swift
│   ├── WorkManager.swift
│   ├── OperationLogManager.swift
│   └── VideoScreenshotExtractor.swift
├── Components/                     # 可复用 UI 组件
│   ├── OpenPanelButton.swift
│   ├── VideoProgressSlider.swift
│   └── VideoComparisonPanel.swift
├── Features/                       # 功能视图 (每个功能一个 View)
│   ├── VideoCropResizeView.swift
│   ├── CropOverlay.swift           # 裁剪框拖拽组件
│   ├── VideoConcatView.swift
│   ├── AudioVideoEditorView.swift
│   ├── VideoScreenshotExtractorView.swift
│   ├── DuplicatePhotoView.swift
│   ├── DuplicateVideoView.swift
│   ├── FileCopyView.swift
│   └── HelpPanelView.swift
└── Assets.xcassets/
```

### 1.2 SwiftUI 布局模板

所有 Feature View **必须** 使用统一布局模板 (详见 BUG_KNOWLEDGE.md `ui` 章节)：

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

- 标题统一由 RootView 的 `.navigationTitle()` 管理，子视图不设置
- 不使用 Spacer() 解决容器填充问题
- 布局问题必须全面排查所有相关视图，不做局部修改

### 1.3 数据流架构

```
用户交互 → View (SwiftUI)
              ↕  @State / @Binding / @ObservedObject
           Service (throws async)
              ↕  纯数据模型
            AVFoundation / FileManager / CryptoKit
```

**核心原则：**
- **Services 层无 UI 依赖** — 不 import SwiftUI/AppKit，仅使用 Foundation + AVFoundation
- **纯内存 + 按需保存** — 数据管道：提取(全量内存) → 多维度筛选 → UI 预览 → 用户确认保存
- **同名文件保护** — `Data.write(to:)` 前必须检查文件是否存在，或使用 `.withoutOverwriting`
- **文件名全局唯一** — 使用原始数据标识（如目标时间戳），避免多数据收敛到同一文件名

### 1.4 Swift 编码规范

| 规范 | 要求 |
|------|------|
| 语言 | 简体中文（UI 文本、注释、commit message） |
| 命名 | View 文件 = PascalCase (`VideoCropResizeView.swift`)，Service 文件 = CamelCase (`videoToolkit.swift`) |
| 异步 | 用 `task()` 修饰符，`@MainActor` 标记 UI 更新方法 |
| 错误处理 | `throws` + 本地化用户友好错误信息，禁止空 catch 块 |
| 类型安全 | 禁止 `as any` / `@ts-ignore`（Swift 中对应 `try!` / `!` 强制解包） |
| AVFoundation | `UTType("...")` 必须用 `.compactMap { $0 }`，禁止 `!` 强制解包；像素格式必须通过 `bitmapInfo` 检测字节序，不硬编码通道顺序 |

### 1.5 并发模型

```swift
// 正确：View 层使用 task() 驱动异步
var body: some View {
    VStack {
        Text(result)
    }
    .task {
        result = await service.doSomething()
    }
}

// 正确：Service 层使用 async throws
actor MyService {
    func process() async throws -> Output {
        // ...
    }
}

// 正确：跨功能状态共享用 @StateObject 在 RootView 持有
@StateObject private var scanModel = DuplicateVideoScanModel()
```

- 长耗时操作（视频处理、文件扫描）使用 `TaskGroup` 并行化
- 跨功能共享状态（如扫描进度）由 RootView 持有 `@StateObject`，子视图通过 init 参数接收

---

## 二、开发工作流 (Development Workflow)

### 2.1 完整开发周期

```
[1] 理解需求
     │
[2] 前置知识检查 (必须 → pre-flight-knowledge-check)
     │
[3] 规划 (如果是多步骤/跨模块任务 → ulw-plan)
     │
[4] 实现 (分解 → 并行委托 subagents)
     │
[5] Review (显著改动后 → review-work)
     │
[6] 同步文档 (功能变更后 → sync-readme-help)
     │
[7] 提交 (git-auto-commit)
     │
[8] 构建验证 (xcode-build-install)
     │
[9] Bug 沉淀 (如果有新的 bug → bug-feedback-tracker)
     │
[10] 知识提炼 (复盘文档产生后 → bug-knowledge-curator)
```

### 2.2 各阶段详细流程

#### Step 2 — 前置知识检查 (MANDATORY → pre-flight-knowledge-check)

**调用 `pre-flight-knowledge-check` 完成以下检查：**

1. 发现项目中的知识库文件（BUG_KNOWLEDGE.md、AGENTS.md 等）
2. 根据本次修改涉及的文件/模块，匹配相关知识条目
3. 完整阅读条目中的场景/根因/规则/例外
4. 将关键约束纳入实现计划

此步骤确保不会重复引入已知问题。如发现新的 bug，在修复前先读对应知识，避免重复踩坑。

#### Step 3 — 规划 (Planning)

当满足以下**任一**条件时，必须先用 `ulw-plan` 做规划：
- 涉及 3+ 个文件修改
- 需要新增/删除功能
- 跨模块调用（View ↔ Service ↔ Model）
- 任务描述模糊或不完整
- 用户明确要求"规划"或"plan"

规划产出应包含：
- 目标描述和验收标准
- 影响范围（哪些文件会改）
- 分解的执行步骤
- 需要的工具/权限

#### Step 4 — 实现 (Implementation)

**分解策略：**
- 每项实现任务必须是原子操作（1-3 个工具调用可完成）
- 独立的任务并行委托给 `deep` / `unspecified-high` 子 agent
- 禁止串行执行独立任务

**委托 Prompt 模板：**
```
TASK: [原子目标]
EXPECTED OUTCOME: [验收标准]
REQUIRED TOOLS: [工具白名单]
MUST DO: [必须执行的约束]
MUST NOT DO: [禁止的行为]
CONTEXT: [文件路径/现有模式/约束条件]
```

**实现约束：**
- 遵循 BUG_KNOWLEDGE.md 中对应模块的规则
- 遵循本文件"架构规范"中的布局模板、数据流模式
- 每完成一个 todo 项立即标记 completed
- 用 `lsp_diagnostics` 验证修改后的文件

#### Step 5 — 审查 (Review)

以下情况**必须**调用 `review-work`：
- 新增 Feature 文件
- 重构 Service 层核心逻辑
- 修改数据流架构
- 涉及像素格式/文件写入/并发控制等高风险代码

review-work 会并行运行 5 个审查 agent（目标验证、代码质量、安全、QA 执行、上下文挖掘），全部通过才算通过。

#### Step 6 — 文档同步（功能变更后 → sync-readme-help）

**触发条件**（满足任意一条即为有变更）：
- Features/ 目录下有文件被新增、删除或重命名
- `Models/ToolFeature.swift` 中的枚举 case 有变化
- 某个功能的界面/行为描述发生了需要记录到文档的变化
- `README.md` 和 `HelpPanelView.swift` 两者中的功能列表不一致（一方有而另一方没有）

**无变更时**：确认后跳过，输出"功能结构无变化，无需同步"。

**有变更时同步流程**：

1. **同步 README.md**（项目根目录，需更新两处）：
   - `## 功能一览` 表格 — 增删功能行，格式：`| **功能名** | 一句话说明 |`
   - `## 详细说明` 各子章节 — 增删对应的 `### N)` 小节，每节包含 bullet point 列表

2. **同步 HelpPanelView.swift**（`Features/HelpPanelView.swift`，需更新一处）：
   - `helpFeatures` 数组 — 增删对应的 `HelpFeature` 元素
   - 每个元素包含：`number`（序号）、`name`（功能名称）、`icon`（SF Symbol）、`summary`（概述）、`details`（详细点列表）

3. **验证一致性**：确认两个文件的功能名称和数量完全一致

**对应关系约束**：
```
README.md 功能一览表  ←→  helpFeatures[]（数量 + 名称一致）
README.md 详细说明小节 ←→  helpFeatures[].details（内容一致）
```

**要点**：
- 以 README.md 为准，HelpPanelView 跟随 README
- 不修改 HelpPanelView 的视图布局、样式或非特征数据部分
- 仅文字润色不需要修改功能列表，只需更新对应位置的描述文本

#### Step 7 — 提交

调用 `git-auto-commit`，遵守以下规则：
- 自动触发前先清理临时文件（clean-logs）
- commit message 格式：`type(scope): 描述`
- 检查是否有 secrets/API key 泄露
- 提交后询问是否需要 push，不自动 push

#### Step 8 — 构建验证

代码提价后运行 `xcode-build-install` 验证编译通过：
- Release arm64 编译
- 安装到 `/Applications`
- 验证 mtime

#### Step 9 — Bug 沉淀（如果 bug/crash 未解决 ≥ 3 轮 → bug-feedback-tracker）

当用户反馈的 Bug 或 Crash 连续多轮未解决时，调用 `bug-feedback-tracker` skill 自动生成复盘文档，存放在 `bug-reports/` 目录。详细流程（触发条件、文档生成、状态跟踪）见该 skill 的说明。

#### Step 10 — 知识提炼（复盘文档产生后 → bug-knowledge-curator）

复盘文档产生后，调用 `bug-knowledge-curator` skill 将 `bug-reports/` 中的经验提炼为结构化知识条目，追加到 `BUG_KNOWLEDGE.md`。提取标准（场景/根因/规则/例外/来源/置信度）及详细流程见该 skill 的说明。

### 2.3 Skill 调用决策树

```
用户请求
│
├─ "编译项目" / "构建" → xcode-build-install
│
├─ "自动提交" / "提交代码" → git-auto-commit
│
├─ "清理日志" / "清理临时文件" → clean-logs
│
├─ "同步文档" / "更新帮助" → sync-readme-help
│
├─ "更新知识库" / "提炼经验" → bug-knowledge-curator
│
├─ bug/crash 未解决 ≥ 3 轮 → bug-feedback-tracker
│
├─ "前置检查" / "知识检查" → pre-flight-knowledge-check
│
├─ 实现后审查 / QA → review-work（内置 skill）
│
├─ 需要规划 / 跨模块任务 → ulw-plan（内置 skill）
│
├─ 清理 AI 代码质量 → remove-ai-slops（内置 skill）
│
├─ 调试复杂问题 → debugging（内置 skill）
│
├─ 前端/UI 视觉任务 → visual-engineering（内置 skill）
```

---

## 三、技术与安全约束

### 3.1 AVFoundation 安全清单

- ☐ `UTType("...")` 使用 `.compactMap { $0 }`，不用 `!`
- ☐ `AVAssetImageGenerator.copyCGImage()` 像素数据通过 `bitmapInfo` 检测字节序
- ☐ 视频帧质量评分使用 Sobel 3×3 + Y 通道，不使用裸像素差分
- ☐ 质量替换逻辑始终执行 ±1s 搜索，不依赖阈值触发

### 3.2 文件 IO 安全清单

- ☐ `Data.write(to:)` 前检查文件是否存在，或使用 `.withoutOverwriting`
- ☐ 文件名使用原始数据标识确保唯一性
- ☐ 中间数据先存内存，用户确认后再写磁盘

### 3.3 并发安全清单

- ☐ UI 更新标记 `@MainActor`
- ☐ 长耗时操作使用 `async/await` + `TaskGroup`
- ☐ 跨功能共享状态由 RootView 持有 `@StateObject`
- ☐ 空 catch 块禁止出现

### 3.4 布局安全清单

- ☐ 所有 Feature View 使用统一布局模板（`ScrollView → VStack → .frame(infinity)`）
- ☐ 标题由 RootView 管理，子视图不设置
- ☐ 布局问题全面排查，不做局部修改

---

## 四、Skills 速查

### 用户安装 (通用 + 项目专用)

| Skill | 路径 | 触发词 | 作用 | 通用性 |
|-------|------|--------|------|--------|
| `bug-knowledge-curator` | `~/.config/opencode/skills/bug-knowledge-curator/` | 更新知识库、提炼经验 | 分析复盘文档 → 知识库，路径可配置 | 🟢 通用 |
| `bug-feedback-tracker` | `~/.config/opencode/skills/bug-feedback-tracker/` | bug 复盘、crash 追踪 | 未解决 bug ≥3 轮生成复盘文档，路径可配置 | 🟢 通用 |
| `pre-flight-knowledge-check` | `~/.config/opencode/skills/pre-flight-knowledge-check/` | 前置检查、知识检查 | 修改前自动读取知识库文件，避免重复踩坑 | 🟢 通用 |
| `xcode-build-install` | `~/.config/opencode/skills/xcode-build-install/` | 编译项目 | Release arm64 编译 + /Applications 安装 | 🟢 通用 |
| `git-auto-commit` | `~/.config/opencode/skills/git-auto-commit/` | 自动提交、继续提交 | 安全提交 + push/pull | 🟢 通用 |
| `clean-logs` | `~/.config/opencode/skills/clean-logs/` | 清理日志、清理临时文件 | 清理 .omo/ /tmp/ 运行时文件 | 🟢 通用 |
| `sync-readme-help` | `~/.config/opencode/skills/sync-readme-help/` | 同步文档、更新帮助 | README ↔ HelpPanelView 双向同步（项目专属） | 🔴 项目专属 |
| `agnes-ai-support` | `~/.config/opencode/skills/agnes-ai-support/` | Agnes AI API | API 接入/排查（与本项目无关） | 🟢 通用 |

### 内置可用

| Skill | 触发词 | 作用 |
|-------|--------|------|
| `review-work` | review work, QA my work | 5 路并行审查 |
| `remove-ai-slops` | 删除 AI 代码坏味 | 清理过度工程/类型不安全代码 |
| `debugging` | debug 复杂问题 | 假设驱动调试循环 |
| `ulw-plan` | plan, 规划 | 探索+规划多步骤任务 |
| `visual-engineering` | visual-engineering | SwiftUI 优化任务（visual-engineering 类别） |

---

## 五、Build & Test

```bash
xed .              # 打开 Xcode 项目
xcodebuild -scheme MacMediaTools -configuration Release build  # Release 编译
```

---

## 六、依赖关系

```
无外部依赖
├── SwiftUI          — UI
├── AVFoundation     — 视频/音频处理
├── AVKit            — 视频播放
├── CryptoKit        — SHA256 哈希
└── AppKit           — NSColor / NSAlert / 文件系统
```

---

*更新于: 2026-07-02*
