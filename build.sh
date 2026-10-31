#!/bin/bash
# MacMediaTools 构建安装脚本（免密码模式）
#
# 与 MediaDownloader 相同的安装模型：
#   /Applications 对 admin 组可写（drwxrwxr-x root admin）→ 直接 rm -rf + cp -R，
#   全程不需要 osascript / sudo，不弹密码。
#
# 唯一例外：历史遗留的 root 属主旧版本（此前用管理员提权安装的）。
#   普通权限无法删除 root 属主文件，需一次性清理（脚本会给出命令），
#   清理之后本脚本永久免密码。
set -e

cd "$(dirname "$0")"

APP_NAME="MacMediaTools"
PROJECT="$APP_NAME.xcodeproj"
SCHEME="$APP_NAME"
BUILT_APP_DIR="$(pwd)/build/DerivedData/Build/Products/Release"
APP="$BUILT_APP_DIR/$APP_NAME.app"
DEST="/Applications/$APP_NAME.app"

# 标准：只允许 /Applications/<App>.app 这一份安装（普通用户权限可写，无需密码）。
# 历史误装可能产生 /Applications/Applications/<App>.app（嵌套目录），
# 会让 Dock / LaunchServices 指向错误副本，安装前先清理。
NESTED_DIR="/Applications/Applications"
if [ -d "$NESTED_DIR/$APP_NAME.app" ]; then
  echo "▶ 清理历史嵌套安装：$NESTED_DIR/$APP_NAME.app"
  rm -rf "$NESTED_DIR/$APP_NAME.app"
  rmdir "$NESTED_DIR" 2>/dev/null || true
fi

# 刷新 LaunchServices 注册，保证从「应用程序」启动的是标准路径
register_app() {
  local lsr="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
  [ -x "$lsr" ] && "$lsr" -f "$DEST" >/dev/null 2>&1 || true
}

echo "▶ 编译 ($SCHEME / Release)..."
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath ./build/DerivedData build > /tmp/mmt-build.log 2>&1 \
  || { echo "✗ 构建失败，日志尾部："; tail -20 /tmp/mmt-build.log; exit 1; }

test -d "$APP" || { echo "✗ 构建产物不存在：$APP"; exit 1; }

# 签名兜底：产物必须通过 codesign 严格校验；否则用 ad-hoc + entitlements 重签
# （sandbox 应用的 entitlements 必须保留，否则首次启动会失败）
if ! codesign --verify --deep --strict "$APP" 2>/dev/null; then
  echo "⚠ 构建产物签名异常，改用 ad-hoc + entitlements 重签"
  codesign --force --sign - \
    --entitlements "$APP_NAME/$APP_NAME.entitlements" \
    --options runtime "$APP"
fi

# 属主即密码门槛：非当前用户属主（历史 root 安装）普通权限不可删除，需一次性 sudo 转换
BUILT_HASH=$(shasum -a 256 "$APP/Contents/MacOS/$APP_NAME" | cut -d' ' -f1)
INSTALLED_HASH=$(shasum -a 256 "$DEST/Contents/MacOS/$APP_NAME" 2>/dev/null | cut -d' ' -f1)

if [ -d "$DEST" ]; then
  OWNER=$(stat -f %Su "$DEST" 2>/dev/null || true)
  ME=$(whoami)

  if [ "$OWNER" != "$ME" ]; then
    echo "⚠ 已安装版本属主为 $OWNER（历史由管理员提权安装），普通权限无法删除。"
    echo "  需一次性清理（仅此一次，此后永久免密码）："
    echo ""
    echo "    sudo rm -rf '$DEST'"
    echo ""
    echo "  执行该命令后重新运行本脚本即可。"
    exit 1
  fi

  if [ -n "$INSTALLED_HASH" ] && [ "$BUILT_HASH" = "$INSTALLED_HASH" ]; then
    echo "✅ 编译产物与已安装版本一致，无需安装：$DEST"
    register_app
    exit 0
  fi
fi

echo "▶ 安装到 $DEST..."
rm -rf "$DEST" || { echo "✗ 无法删除旧版本，请手动处理后重试"; exit 1; }
cp -R "$APP" "$DEST"
register_app

# 验证：mtime 必须 >= 构建产物
BUILT_MTIME=$(stat -f "%m" "$APP")
INSTALLED_MTIME=$(stat -f "%m" "$DEST")
echo ""
if [ "$INSTALLED_MTIME" -ge "$BUILT_MTIME" ] 2>/dev/null; then
  echo "✅ 完成：$DEST"
  echo "   启动：open \"$DEST\""
else
  echo "⚠ 安装可能过期（mtime 校验失败），请检查 $DEST"
  exit 1
fi