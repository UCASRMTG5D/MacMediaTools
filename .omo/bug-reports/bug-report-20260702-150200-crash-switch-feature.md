# Bug/Crash 复盘文档

## 📋 基本信息
- **Bug ID**: BUG-20260702-150200-crash-switch-feature
- **生成时间**: 2026-07-02 15:02:00
- **触发原因**: 用户反馈「切换功能时出现 crash」，Agent 主动复盘记录
- **状态**: 🟢 已解决

---

## 🐛 问题描述

### 用户反馈
> **用户**: "ulw 在切换功能的时候出现 crash"
> **时间**: 2026-07-02 14:50:00
> **上下文**: 导航切换到「批量截图」功能时，主线程崩溃

### 崩溃日志摘要
```
Thread 0 Crashed:: Dispatch queue: com.apple.main-thread
EXC_BREAKPOINT (SIGTRAP)
Swift runtime failure: Unexpectedly found nil while unwrapping an Optional value
closure #1 in closure #1 in closure #1 in VideoScreenshotExtractorView.sidebarPanel.getter
  (VideoScreenshotExtractorView.swift:111)
```

---

## 🔧 修复过程

| 轮次 | 时间 | Agent 动作 | 涉及文件 | 结果 |
|------|------|------------|----------|------|
| 1 | 14:51:00 | 定位根因：`UTType("...")!` 强制解包 nil → 改用 `.compactMap { $0 }` | `VideoScreenshotExtractorView.swift:111` | 🟢 已解决 |

---

## 📊 问题分析

### Root Cause
`VideoScreenshotExtractorView.swift` 第 111 行：
```swift
// ❌ 强制解包 — 崩溃
mode: .file(allowedTypes: [.movie, .mpeg4Movie, .quickTimeMovie,
    UTType("public.avi")!, UTType("public.flv")!, UTType("com.microsoft.wmv")!],
    allowsMultipleSelection: false)
```

`UTType("public.flv")` 和 `UTType("com.microsoft.wmv")` 在部分 macOS 系统上不是已注册的 UTI，返回 `nil`。强制解包 `!` 触发 `EXC_BREAKPOINT`。

### 修复
```swift
// ✅ 安全写法
mode: .file(allowedTypes: [.movie, .mpeg4Movie, .quickTimeMovie,
    UTType("public.avi"), UTType("public.flv"), UTType("com.microsoft.wmv")
].compactMap { $0 }, allowsMultipleSelection: false)
```

静默跳过不存在的 UTI，与 `OpenPanelButton` 内部 `.mediaFiles` 模式保持一致。

### 引入原因
重构 `Button + selectVideo()` → `OpenPanelButton` 时，漏掉了原有代码的 `.compactMap { $0 }` 安全处理。原版 `selectVideo()` 使用的是安全写法。

---

## 📎 相关文件

| 文件 | 修改类型 | 状态 |
|------|----------|------|
| `MacMediaTools/Features/VideoScreenshotExtractorView.swift` | 修复 1 行 | ✅ 已提交 |

---

## 💡 经验教训

1. 所有 `UTType("...")` 动态查询必须使用可选绑定或 `.compactMap`，禁止 `!` 强制解包
2. 此类问题不会在编译时暴露，只能在运行时触发
3. 建议全局搜索 `UTType("...")!` 模式防止复发

---

*文档由 Agent 主动复盘生成，Bug Feedback Tracker Skill v1.0.0*
