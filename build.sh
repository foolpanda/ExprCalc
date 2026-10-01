#!/bin/bash
#  ExprCalc 一键构建脚本（macOS 14+ / Xcode 15+ / Swift 5.9+）
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
DERIVED_DATA="${SCRIPT_DIR}/.build"
PROJECT_NAME="ExprCalc"

usage() {
    echo "用法: ./build.sh [debug|release|test|app|verify|clean]"
    echo "  debug   命令行编译 Debug"
    echo "  release 命令行编译 Release"
    echo "  test    运行 XCTest"
    echo "  app     产出 ExprCalc.app"
    echo "  verify  不依赖 Xcode，纯 Swift 验证引擎"
    echo "  clean   清理"
    exit 0
}
[[ $# -lt 1 ]] && usage
CMD="$1"

if [[ ! -d "${PROJECT_NAME}.xcodeproj" ]]; then
    echo "ℹ️  未找到 ${PROJECT_NAME}.xcodeproj"
    echo "   请确认当前目录为工程根目录（与 ExprCalc.xcodeproj 同级）"
fi

# 若 xcode-select 指向 CommandLineTools，自动改用 /Applications/Xcode.app
if ! xcodebuild -version >/dev/null 2>&1; then
    if [[ -x /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild ]]; then
        export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
        echo "ℹ️  已自动使用 /Applications/Xcode.app（xcode-select 当前指向 CommandLineTools）"
    else
        echo "⚠️  未找到可用的 Xcode，请安装或执行：sudo xcode-select -s /Applications/Xcode.app"
    fi
fi

case "$CMD" in
    verify)
        echo "🔬 验证表达式引擎（针对 ExprCalc/ExprEvaluator.swift 编译验证）..."
        mkdir -p "$DERIVED_DATA"
        swiftc -O "${PROJECT_NAME}/ExprEvaluator.swift" verify_engine.swift -o "$DERIVED_DATA/verify_engine"
        "$DERIVED_DATA/verify_engine"
        ;;
    debug)
        xcodebuild -project "${PROJECT_NAME}.xcodeproj" -scheme "${PROJECT_NAME}" \
            -configuration Debug -derivedDataPath "$DERIVED_DATA" -destination 'platform=macOS' build
        echo "✅ Debug 构建成功"
        ;;
    release)
        xcodebuild -project "${PROJECT_NAME}.xcodeproj" -scheme "${PROJECT_NAME}" \
            -configuration Release -derivedDataPath "$DERIVED_DATA" -destination 'platform=macOS' build
        echo "✅ Release 构建成功"
        ;;
    test)
        xcodebuild -project "${PROJECT_NAME}.xcodeproj" -scheme "${PROJECT_NAME}" \
            -configuration Debug -derivedDataPath "$DERIVED_DATA" -destination 'platform=macOS' test
        ;;
    app)
        xcodebuild -project "${PROJECT_NAME}.xcodeproj" -scheme "${PROJECT_NAME}" \
            -configuration Release -derivedDataPath "$DERIVED_DATA" -destination 'platform=macOS' build
        APP=$(find "$DERIVED_DATA" -name "${PROJECT_NAME}.app" -type d | head -1)
        rm -rf "./${PROJECT_NAME}.app"
        cp -R "$APP" "./${PROJECT_NAME}.app"
        xattr -cr "./${PROJECT_NAME}.app" 2>/dev/null || true
        echo "✅ 已生成 ./${PROJECT_NAME}.app  （运行：open ./${PROJECT_NAME}.app）"
        ;;
    clean)
        rm -rf "$DERIVED_DATA" "ExprCalc.app"
        echo "🧹 已清理"
        ;;
    *) usage ;;
esac
