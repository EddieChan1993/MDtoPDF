#!/usr/bin/env python3
"""
GrapePress App Icon — 平面设计风格
深紫背景 + 纯色葡萄粒 + 平面叶子
输出: AppIcon.icns（供 build.sh 打入 .app bundle）
"""
import subprocess, os, shutil, json

# ── 平面 SVG ──────────────────────────────────────────────────────────────────
SVG = """\
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <defs>
    <!-- macOS 图标圆角 ~22.5% = 230px -->
    <clipPath id="shape">
      <rect width="1024" height="1024" rx="230" ry="230"/>
    </clipPath>
  </defs>
  <g clip-path="url(#shape)">

    <!-- 背景：深紫 -->
    <rect width="1024" height="1024" fill="#3B0764"/>

    <!-- 装饰：右上角淡色圆 -->
    <circle cx="870" cy="154" r="210" fill="#4C1D95"/>

    <!-- 茎 -->
    <line x1="512" y1="440" x2="512" y2="268"
          stroke="#A78BFA" stroke-width="22" stroke-linecap="round"/>

    <!-- 左叶：放大 + MD 字幕（整组旋转保持文字与叶同向） -->
    <g transform="rotate(-28,432,244)">
      <ellipse cx="432" cy="244" rx="162" ry="92" fill="#34D399"/>
      <text x="432" y="244"
            font-family="Arial Black,Arial,Helvetica,sans-serif"
            font-weight="900" font-size="80" fill="white"
            text-anchor="middle" dominant-baseline="central"
            letter-spacing="-2">MD</text>
    </g>

    <!-- 右叶：放大 + PDF 字幕 -->
    <g transform="rotate(26,596,250)">
      <ellipse cx="596" cy="250" rx="148" ry="84" fill="#10B981"/>
      <text x="596" y="250"
            font-family="Arial Black,Arial,Helvetica,sans-serif"
            font-weight="900" font-size="64" fill="white"
            text-anchor="middle" dominant-baseline="central"
            letter-spacing="-1">PDF</text>
    </g>

    <!-- 葡萄粒：6颗，3-2-1 倒三角 -->
    <circle cx="326" cy="522" r="88" fill="#C4B5FD"/>
    <circle cx="512" cy="522" r="88" fill="#C4B5FD"/>
    <circle cx="698" cy="522" r="88" fill="#C4B5FD"/>

    <circle cx="419" cy="708" r="88" fill="#C4B5FD"/>
    <circle cx="605" cy="708" r="88" fill="#C4B5FD"/>

    <circle cx="512" cy="894" r="88" fill="#C4B5FD"/>

  </g>
</svg>
"""

DIR    = os.path.expanduser("~/MDtoPDF")
SVG_F  = os.path.join(DIR, "AppIcon.svg")
ISET   = os.path.join(DIR, "AppIcon.iconset")   # iconutil 要求 .iconset 后缀
ICNS   = os.path.join(DIR, "AppIcon.icns")

# iconutil 要求的文件名 → 实际像素尺寸
SPEC = [
    ("icon_16x16.png",      16),
    ("icon_16x16@2x.png",   32),
    ("icon_32x32.png",      32),
    ("icon_32x32@2x.png",   64),
    ("icon_128x128.png",   128),
    ("icon_128x128@2x.png",256),
    ("icon_256x256.png",   256),
    ("icon_256x256@2x.png",512),
    ("icon_512x512.png",   512),
    ("icon_512x512@2x.png",1024),
]

def svg_to_png(svg_path, out_path, size):
    """用 rsvg-convert 把 SVG 转为 PNG。"""
    r = subprocess.run(
        ["rsvg-convert", "-w", str(size), "-h", str(size), "-o", out_path, svg_path],
        capture_output=True
    )
    return r.returncode == 0

def main():
    # 1. 写 SVG
    with open(SVG_F, "w") as f:
        f.write(SVG)
    print(f"✓ SVG 已生成")

    # 2. 检查 rsvg-convert
    if subprocess.run(["which", "rsvg-convert"], capture_output=True).returncode != 0:
        print("✗ 缺少 rsvg-convert，请先安装：")
        print("  brew install librsvg")
        return

    # 3. 生成各尺寸 PNG → AppIcon.iconset/
    shutil.rmtree(ISET, ignore_errors=True)
    os.makedirs(ISET)

    for fname, size in SPEC:
        out = os.path.join(ISET, fname)
        if svg_to_png(SVG_F, out, size):
            print(f"  ✓ {fname} ({size}x{size})")
        else:
            print(f"  ✗ {fname} 失败")

    # 4. iconutil → .icns
    r = subprocess.run(
        ["iconutil", "--convert", "icns", "--output", ICNS, ISET],
        capture_output=True, text=True
    )
    if r.returncode == 0:
        size_kb = os.path.getsize(ICNS) // 1024
        print(f"\n✅ AppIcon.icns 已生成（{size_kb} KB）")
        print(f"   路径: {ICNS}")
    else:
        print(f"✗ iconutil 失败: {r.stderr}")

if __name__ == "__main__":
    main()
