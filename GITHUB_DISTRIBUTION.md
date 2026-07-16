# GitHub 分发指南（Mac App Store 之外）

本文件说明如何把 MacMediaTools 直接发布到 GitHub Releases，让用户无需经过 App Store 即可下载安装。

> 与 App Store 路线**相互独立**：两条线使用不同的签名证书，需要各自构建一次。代码相同，仅签名身份与分发方式不同。
> 本文档不涉及 App Store 提交（见 `APPSTORE_US_SUBMISSION.md`）。

---

## 为什么不能直接发裸 .app

从浏览器下载的 macOS 软件会被 **Gatekeeper** 拦截，除非满足：

1. 用 **Developer ID Application** 证书签名（App Store 用的是 Apple Distribution，不能混用）
2. 通过 Apple **公证（Notarization）** 扫描
3. 把公证 ticket **staple** 到包上（离线也可验证）
4. 打包成 `.dmg` 或 `.pkg` 再发布（裸 `.app` 也能发，但 `.dmg` 体验更好）

未签名/未公证的包用户打开时会看到「Apple 无法检查其是否含恶意软件」，需手动右键→打开绕过，体验差且易被误判为恶意软件。

---

## 当前项目配置核对

| 项目 | 当前值 | GitHub 分发要求 | 状态 |
|------|--------|----------------|------|
| `DEVELOPMENT_TEAM` | `X8DYHGXUJH` | 同一 team | ✅ |
| `ENABLE_HARDENED_RUNTIME` | `YES` | 公证**必须**开启 | ✅ 已满足 |
| 签名身份 | 当前为 Apple Distribution（App Store） | 需切到 **Developer ID Application** | ⚠️ 需切换 |
| App Sandbox | 开启（`user-selected.read-write` + `downloads.read-write`） | Developer ID **支持**这两个能力 | ✅ 无需改代码 |
| Entitlements 文件 | `MacMediaTools.entitlements` | Developer ID 兼容 | ✅ |

**结论**：无需修改任何 Swift 代码或 entitlements。只需更换签名身份并走 Developer ID 分发 + 公证流程。

---

## 前置准备（一次性）

### 1. Developer ID Application 证书

- 必须是 **Apple Developer Program 付费账号**，且由 **Account Holder** 生成。
- 生成方式（任选其一）：
  - Xcode → `Settings → Accounts` → 选中 team → `Manage Certificates...` → `+` → `Developer ID Application`
  - 或 developer.apple.com → `Certificates, Identifiers & Profiles` → `Create a Certificate` → `Developer ID Application`，上传 CSR 后下载 `.cer` 并双击装入钥匙串。

### 2. App Store Connect API Key（用于公证）

- 登录 App Store Connect → `Users and Access` → `Integrations` → `App Store Connect API` → `Generate`
- 下载 `AuthKey_XXXX.p8`（**仅能下载一次**，妥善保管）
- 记录 **Key ID**（10 字符）和 **Issuer ID**（页面顶部 UUID）
- 用 `notarytool` 时通过 keychain profile 引用，避免明文密码：

```bash
xcrun notarytool store-credentials "AC_API" \
  --key /path/to/AuthKey_XXXX.p8 \
  --key-id XXXXXXXXXX \
  --issuer <issuer-uuid>
```

---

## 构建与分发流程

### 方式 A — Xcode 图形界面（推荐首次操作）

1. Xcode 顶部运行目标选 **My Mac**（不要选模拟器）
2. `Product → Archive`
3. Archive 完成后自动弹出 Organizer（或 `Window → Organizer` → `Archives` 标签）
4. 选中 archive → **Distribute App** → 选 **Developer ID**（不是 App Store Connect）→ **Upload**
5. 等待公证完成（Xcode 会显示状态；也可在 email / App Store Connect 查）
6. 公证通过后 → **Export** 导出（选 `.pkg` 或带公证的 `.app`）
7. 用下方「打包成 DMG」步骤生成 `.dmg`
8. 在 GitHub 建 Release，上传 `.dmg`

### 方式 B — 命令行（可脚本化 / 将来 CI 用）

#### 1. 导出 Developer ID 签名的包

新建 `ExportOptions.plist`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>X8DYHGXUJH</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
</dict>
</plist>
```

```bash
xcodebuild -archivePath build/MacMediaTools.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist ExportOptions.plist
```

导出后得到 `build/export/MacMediaTools.app`（已用 Developer ID 签名）。

#### 2. 打包成 DMG（可选但推荐）

```bash
# 安装 create-dmg（需 brew）
brew install create-dmg

create-dmg \
  --volname "MacMediaTools" \
  --window-pos 200 120 \
  --window-size 500 300 \
  --icon-size 100 \
  --icon "MacMediaTools.app" 130 130 \
  --hide-extension "MacMediaTools.app" \
  --app-drop-link 370 130 \
  "build/MacMediaTools.dmg" \
  "build/export/MacMediaTools.app"
```

> 纯 `.app` 或 `.zip` 也可直接发，但 `.dmg` 提供「拖到 Applications」的标准体验。

#### 3. 公证

```bash
xcrun notarytool submit "build/MacMediaTools.dmg" \
  --keychain-profile "AC_API" \
  --wait
```

#### 4. 钉 ticket（让离线也能通过 Gatekeeper）

```bash
xcrun stapler staple "build/MacMediaTools.dmg"
# 验证
xcrun stapler validate "build/MacMediaTools.dmg"
```

#### 5. 发布到 GitHub Releases

- 在仓库 `Releases` 页面建新 Release（建议带 tag，如 `v1.0.0-github` 以区别于 App Store 构建）
- 上传 `MacMediaTools.dmg`
- 在 Release Notes 注明：macOS 13.0+，Apple Silicon / Intel 通用（如已设 `ARCHS=arm64 x86_64`）

---

## 验证清单（发布前必做）

- [ ] `codesign -dv --verbose=4 build/export/MacMediaTools.app` 显示 `Authority=Developer ID Application`
- [ ] `spctl -a -vv -t install build/export/MacMediaTools.app` 返回 `accepted`（在另一台 Gatekeeper 开启的 Mac 上测试）
- [ ] notarytool 状态为 `Accepted`
- [ ] stapler validate 通过
- [ ] 下载链接在 GitHub Releases 可见，文件大小与本地一致

---

## 与 App Store 路线的区别小结

| 维度 | App Store | GitHub 直接分发 |
|------|-----------|----------------|
| 签名证书 | Apple Distribution | Developer ID Application |
| 沙盒 | 强制 | 推荐（本项目已开启） |
| 公证 | 不需要（审核代替） | **必须** |
| 更新分发 | Apple 托管 | 开发者自行（GitHub Release） |
| 内购 / Game Center | 可用 | 不可用 |
| 构建次数 | 一份 | 需单独再构建一份 |

---

## 常见问题

**Q：能否同一份 .xcarchive 既上 App Store 又发 GitHub？**
A：不能。签名身份不同，必须分别 `exportArchive`（method 分别为 `app-store` 和 `developer-id`）。

**Q：用户下载后提示「已损坏」？**
A：说明未公证或 ticket 未 staple。重新走公证 + `stapler staple` 步骤。

**Q：能否发裸 .zip 包 .app？**
A：可以，但 Gatekeeper 仍要求签名 + 公证。zip 内 .app 需已公证并 staple（staple 对 .app 本身有效，对 zip 容器无效，但解压后 .app 自带 ticket）。

**Q：Developer ID 证书和 App Store 证书能共存吗？**
A：可以，同一钥匙串可同时持有两种证书，Xcode 按 export method 自动选择。
