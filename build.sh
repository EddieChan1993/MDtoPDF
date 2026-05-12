#!/usr/bin/env bash
# MDtoPDF 打包脚本
# 用法: bash build.sh
# 产物: MDtoPDF.app（当前目录）

set -euo pipefail

# ─── 颜色输出 ─────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
step() { echo -e "\n${BLUE}▶ $1${NC}"; }
ok()   { echo -e "${GREEN}  ✓ $1${NC}"; }
warn() { echo -e "${YELLOW}  ⚠ $1${NC}"; }
err()  { echo -e "${RED}  ✗ $1${NC}"; exit 1; }

# ─── 路径配置 ─────────────────────────────────────────────
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY_NAME="MDtoPDF"          # SPM target 名 / 可执行文件名，不要改
APP_DISPLAY_NAME="GrapePress"  # 显示给用户的 app 名字
SOURCES_DIR="$DIR/Sources/$BINARY_NAME"
PACKAGE_FILE="$DIR/Package.swift"
BUILD_DIR="$DIR/.build/release"
OUTPUT_APP="$DIR/$APP_DISPLAY_NAME.app"

# ─── 生成 App Icon ────────────────────────────────────────
step "生成 App Icon"

ICNS_FILE="$DIR/AppIcon.icns"
if [ ! -f "$ICNS_FILE" ]; then
    if command -v python3 &>/dev/null && [ -f "$DIR/make_icon.py" ]; then
        python3 "$DIR/make_icon.py" && ok "AppIcon.icns 已生成" || warn "图标生成失败，将跳过图标"
    else
        warn "未找到 make_icon.py 或 python3，跳过图标生成"
    fi
else
    ok "AppIcon.icns 已存在，跳过生成"
fi

# ─── 环境检查 ─────────────────────────────────────────────
step "检查环境"

if ! command -v swift &> /dev/null; then
    err "未找到 swift 命令，请先安装 Xcode 或 Xcode Command Line Tools"
fi

SWIFT_VER=$(swift --version 2>&1 | head -1)
ok "Swift: $SWIFT_VER"

MACOS_VER=$(sw_vers -productVersion)
MACOS_MAJOR=$(echo "$MACOS_VER" | cut -d. -f1)
if [ "$MACOS_MAJOR" -lt 13 ]; then
    err "需要 macOS 13.0+，当前版本: $MACOS_VER"
fi
ok "macOS: $MACOS_VER"

# 检查源文件是否都在
REQUIRED=(MDtoPDFApp.swift ContentView.swift AppViewModel.swift MarkdownParser.swift PDFExporter.swift)
for f in "${REQUIRED[@]}"; do
    if [ ! -f "$DIR/$f" ]; then
        err "缺少源文件: $f"
    fi
done
ok "源文件完整（${#REQUIRED[@]} 个）"

# ─── 创建 SPM Package 结构 ────────────────────────────────
step "准备 Swift Package"

mkdir -p "$SOURCES_DIR"
for f in "${REQUIRED[@]}"; do
    cp -f "$DIR/$f" "$SOURCES_DIR/$f"
done
ok "源文件已复制到 Sources/$BINARY_NAME/"

cat > "$PACKAGE_FILE" << 'PKGEOF'
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MDtoPDF",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MDtoPDF",
            path: "Sources/MDtoPDF"
        )
    ]
)
PKGEOF
ok "Package.swift 已生成"

# ─── 编译 Release ─────────────────────────────────────────
step "编译 Release（首次可能需要几分钟）"

cd "$DIR"
if swift build -c release 2>&1; then
    ok "编译成功"
else
    err "编译失败，请查看上方错误信息"
fi

EXECUTABLE="$BUILD_DIR/$BINARY_NAME"
if [ ! -f "$EXECUTABLE" ]; then
    err "编译产物未找到: $EXECUTABLE"
fi

# ─── 创建 .app Bundle ────────────────────────────────────
step "创建 .app Bundle"

# 如果 app 正在运行，先关闭
if pgrep -x "$APP_DISPLAY_NAME" &>/dev/null; then
    warn "检测到 $APP_DISPLAY_NAME 正在运行，正在关闭..."
    pkill -x "$APP_DISPLAY_NAME" || true
    sleep 1
fi

rm -rf "$OUTPUT_APP"
mkdir -p "$OUTPUT_APP/Contents/MacOS"
mkdir -p "$OUTPUT_APP/Contents/Resources"
ok "Bundle 目录结构已创建"

# 复制可执行文件（重命名为 display name，与 CFBundleExecutable 对应）
cp "$EXECUTABLE" "$OUTPUT_APP/Contents/MacOS/$APP_DISPLAY_NAME"
chmod +x "$OUTPUT_APP/Contents/MacOS/$APP_DISPLAY_NAME"
ok "可执行文件已复制"

# 复制图标
if [ -f "$ICNS_FILE" ]; then
    cp "$ICNS_FILE" "$OUTPUT_APP/Contents/Resources/AppIcon.icns"
    ok "AppIcon.icns 已复制到 Resources/"
else
    warn "AppIcon.icns 不存在，bundle 将无图标"
fi

# 写入 Info.plist
cat > "$OUTPUT_APP/Contents/Info.plist" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_DISPLAY_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_DISPLAY_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.localuser.MDtoPDF</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>$APP_DISPLAY_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHumanReadableCopyright</key>
    <string>Local Build</string>
</dict>
</plist>
PLISTEOF
ok "Info.plist 已写入"

# ─── 代码签名（ad-hoc） ────────────────────────────────────
step "代码签名（ad-hoc，本机运行使用）"

codesign \
    --force \
    --deep \
    --sign - \
    "$OUTPUT_APP" 2>&1 && ok "签名完成" || warn "签名失败（可能影响文件拖放权限，通常不影响基本运行）"

# ─── 完成 ─────────────────────────────────────────────────
step "打包完成"

APP_SIZE=$(du -sh "$OUTPUT_APP" | cut -f1)
echo -e "\n${CYAN}┌──────────────────────────────────────────────"
echo -e "│  产物路径: $OUTPUT_APP"
echo -e "│  文件大小: $APP_SIZE"
echo -e "└──────────────────────────────────────────────${NC}"
echo ""
echo -e "  运行方式："
echo -e "    双击 $APP_DISPLAY_NAME.app  （推荐）"
echo -e "    open \"$OUTPUT_APP\""
echo ""
echo -e "  如果 macOS 提示"无法验证开发者"："
echo -e "    右键 → 打开 → 点"打开"  （仅首次需要）"
echo -e "    或: xattr -cr \"$OUTPUT_APP\""
echo ""
