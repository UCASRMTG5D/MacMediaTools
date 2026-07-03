# MacMediaTools — Agent Guide

## Project Overview

macOS SwiftUI(Swift) 多媒体工具箱（纯本地，无外部依赖），使用 AVFoundation/AVKit/CryptoKit。

## CRITICAL: Read Bug Knowledge Before Coding

**Before making ANY code changes, you MUST read `BUG_KNOWLEDGE.md` to learn from past bugs and avoid reintroducing known issues.**

The knowledge base is organized by module (media-processing, ui, build-deploy, file-io) and each entry includes precise scene, root cause, rules, and exceptions. Read the sections relevant to the code you're about to change.

## Build & Test

```bash
xed .              # 打开 Xcode 项目
xcodebuild -scheme MacMediaTools -configuration Release build  # Release 编译
```

## Conventions

- SwiftUI + NavigationSplitView layout pattern: `ScrollView { VStack }.frame(maxWidth:.infinity, maxHeight:.infinity)`
- Project language: 简体中文（用户界面和注释使用中文）
- File naming: PascalCase for Views, CamelCase for services/utilities
- All Feature Views live under `Features/`, services under `Services/`, components under `Components/`
- Use `task()` for async work, `@MainActor` for UI updates
- Error handling: `throws` + localized user-facing messages, no empty catch blocks

## Skills Available

- `bug-knowledge-curator` — 分析 bug-reports/ 沉淀知识到 BUG_KNOWLEDGE.md
- `bug-feedback-tracker` — 自动追踪未解决的 bug/crash 生成复盘文档
- `xcode-build-install` — 编译并安装到 /Applications
- `git-auto-commit` — 自动提交代码
- `clean-logs` — 清理临时文件
