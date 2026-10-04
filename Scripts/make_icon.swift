//  ExprCalc 图标生成脚本
//  用法: swift /tmp/make_icon.swift <输出目录>
//  渲染: 蓝色渐变圆角方块 + 白色 "√x"（SF Pro Rounded，回退 HelveticaNeue-Bold）

import AppKit
import CoreText

let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "."

// MARK: - 字体：系统字体 + Rounded 设计，回退 HelveticaNeue-Bold

func makeBoldRoundedFont(size: CGFloat) -> CTFont {
    let sysDesc = NSFont.systemFont(ofSize: size, weight: .bold).fontDescriptor
    let roundedDesc = sysDesc.withDesign(.rounded) ?? sysDesc
    let rounded = CTFontCreateWithFontDescriptor(roundedDesc as CTFontDescriptor, size, nil)
    let fullName = CTFontCopyFullName(rounded) as String
    if fullName.lowercased().contains("rounded") {
        print("字体: \(fullName)")
        return rounded
    }
    print("字体: HelveticaNeue-Bold（Rounded 不可用，回退）")
    return CTFontCreateWithName("HelveticaNeue-Bold" as CFString, size, nil)
}

// MARK: - 渲染一帧图标

func render(size: CGFloat, font: CTFont) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext  // 原点左下，y 向上

    // 形状：1024 画布内 824 圆角方块（Apple macOS 图标网格）
    let inset = size * 100.0 / 1024.0
    let shape = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let radius = shape.width * 0.224
    let path = CGPath(roundedRect: shape, cornerWidth: radius, cornerHeight: radius, transform: nil)

    let space = CGColorSpaceCreateDeviceRGB()

    // 主渐变：左上亮蓝 → 右下深蓝
    cg.saveGState()
    cg.addPath(path)
    cg.clip()
    let gradient = CGGradient(
        colorsSpace: space,
        colors: [
            CGColor(srgbRed: 0.33, green: 0.65, blue: 1.00, alpha: 1),
            CGColor(srgbRed: 0.09, green: 0.35, blue: 0.88, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!
    cg.drawLinearGradient(
        gradient,
        start: CGPoint(x: shape.minX, y: shape.maxY),
        end: CGPoint(x: shape.maxX, y: shape.minY),
        options: []
    )

    // 顶部高光
    let gloss = CGGradient(
        colorsSpace: space,
        colors: [
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.30),
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0),
        ] as CFArray,
        locations: [0, 1]
    )!
    cg.drawLinearGradient(
        gloss,
        start: CGPoint(x: shape.midX, y: shape.maxY),
        end: CGPoint(x: shape.midX, y: shape.minY + shape.height * 0.58),
        options: []
    )
    cg.restoreGState()

    // 细白描边，增加轮廓感
    cg.saveGState()
    cg.setLineWidth(max(1, size * 2.0 / 1024.0))
    cg.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.22))
    cg.addPath(path)
    cg.strokePath()
    cg.restoreGState()

    // 主文字 "√x"，带柔和投影，光学居中
    let attr = CFAttributedStringCreate(
        nil,
        "√x" as CFString,
        [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
        ] as CFDictionary
    )!
    let line = CTLineCreateWithAttributedString(attr)
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

    cg.saveGState()
    cg.setShadow(
        offset: CGSize(width: 0, height: -size * 7.0 / 1024.0),
        blur: size * 18.0 / 1024.0,
        color: CGColor(srgbRed: 0, green: 0.05, blue: 0.3, alpha: 0.35)
    )
    let cx = shape.midX
    let cy = shape.midY + shape.height * 0.015
    cg.textPosition = CGPoint(x: cx - bounds.midX, y: cy - bounds.midY)
    CTLineDraw(line, cg)
    cg.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - 输出全部尺寸（标准 macOS 10 文件命名）

let font = makeBoldRoundedFont(size: 460)
let specs: [(String, CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for (name, pixels) in specs {
    // 每个尺寸独立矢量渲染，小尺寸更清晰
    let rep = render(size: pixels, font: makeBoldRoundedFont(size: 460 * pixels / 1024))
    guard let data = rep.representation(using: .png, properties: [:]) else {
        print("✗ 生成 \(name) 失败")
        continue
    }
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    try data.write(to: url)
    print("✓ \(name)  \(Int(pixels))×\(Int(pixels))")
}
print("完成")
