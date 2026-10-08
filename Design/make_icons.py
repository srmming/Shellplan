"""
生成 App 图标：一个等轴测的白模房间（带门洞和窗洞），外面是扫描取景框，前面一条尺寸线。
输出三个矢量 SVG（浅色 / 深色 / 着色），再用 rsvg-convert 渲染成 1024×1024 PNG 放进 AppIcon.appiconset。

用法：python3 Design/make_icons.py
"""

import os
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
ICONSET = os.path.join(HERE, "..", "RoomScan", "Assets.xcassets", "AppIcon.appiconset")

THEMES = {
    "light": dict(bg_top="#3B82F6", bg_bottom="#1E3A8A", hole="#1D4ED8",
                  wall_left="#FFFFFF", wall_right="#DCE6F5", floor="#B9C9E4", edge="#FFFFFF",
                  bracket="#FFFFFF", dim="#FBBF24", bracket_opacity="0.95"),
    "dark": dict(bg_top="#1E293B", bg_bottom="#020617", hole="#0F172A",
                 wall_left="#F1F5F9", wall_right="#CBD5E1", floor="#64748B", edge="#F8FAFC",
                 bracket="#93C5FD", dim="#FBBF24", bracket_opacity="0.9"),
    # 着色图标：系统会按亮度上色，所以只用灰度，背景是纯黑
    "tinted": dict(bg_top="#000000", bg_bottom="#000000", hole="#000000",
                   wall_left="#FFFFFF", wall_right="#C8C8C8", floor="#7A7A7A", edge="#FFFFFF",
                   bracket="#FFFFFF", dim="#E6E6E6", bracket_opacity="0.85"),
}

# 等轴测房间的关键点（1024 画布）
B = (512, 380)                  # 地面后角
R = (772, 530)                  # 地面右角
L = (252, 530)                  # 地面左角
F = (512, 680)                  # 地面前角
H = 225                         # 墙高（像素）
B2, R2, L2 = (B[0], B[1] - H), (R[0], R[1] - H), (L[0], L[1] - H)


def pts(*ps):
    return " ".join(f"{x:g},{y:g}" for x, y in ps)


def on_right_wall(t, z):
    return (B[0] + t * (R[0] - B[0]), B[1] + t * (R[1] - B[1]) - z)


def on_left_wall(t, z):
    return (L[0] + t * (B[0] - L[0]), L[1] + t * (B[1] - L[1]) - z)


def svg(c):
    door = [on_right_wall(0.55, 0), on_right_wall(0.8, 0), on_right_wall(0.8, 150), on_right_wall(0.55, 150)]
    window = [on_left_wall(0.3, 80), on_left_wall(0.65, 80), on_left_wall(0.65, 170), on_left_wall(0.3, 170)]

    # 尺寸线：沿左前地面边 L→F，向外偏移
    ox, oy = -24, 42
    d0, d1 = (L[0] + ox, L[1] + oy), (F[0] + ox, F[1] + oy)
    tick = (12, -21)  # 垂直于尺寸线的短刻度

    # 取景框四个角
    a, b, n = 150, 874, 120

    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{c['bg_top']}"/>
      <stop offset="1" stop-color="{c['bg_bottom']}"/>
    </linearGradient>
  </defs>
  <rect width="1024" height="1024" fill="url(#bg)"/>

  <g fill="none" stroke="{c['bracket']}" stroke-width="34" stroke-linecap="round" stroke-linejoin="round" opacity="{c['bracket_opacity']}">
    <path d="M{a},{a + n} V{a} H{a + n}"/>
    <path d="M{b - n},{a} H{b} V{a + n}"/>
    <path d="M{b},{b - n} V{b} H{b - n}"/>
    <path d="M{a + n},{b} H{a} V{b - n}"/>
  </g>

  <g transform="translate(0,60)">
  <polygon points="{pts(L, B, R, F)}" fill="{c['floor']}"/>
  <polygon points="{pts(L, B, B2, L2)}" fill="{c['wall_left']}"/>
  <polygon points="{pts(B, R, R2, B2)}" fill="{c['wall_right']}"/>
  <polygon points="{pts(*window)}" fill="{c['hole']}"/>
  <polygon points="{pts(*door)}" fill="{c['hole']}"/>
  <polyline points="{pts(L2, B2, R2)}" fill="none" stroke="{c['edge']}" stroke-width="10" stroke-linejoin="round"/>
  <line x1="{B[0]}" y1="{B[1]}" x2="{B2[0]}" y2="{B2[1]}" stroke="{c['bg_bottom']}" stroke-opacity="0.15" stroke-width="4"/>

  <g stroke="{c['dim']}" stroke-width="14" stroke-linecap="round">
    <line x1="{d0[0]}" y1="{d0[1]}" x2="{d1[0]}" y2="{d1[1]}"/>
    <line x1="{d0[0] - tick[0]}" y1="{d0[1] - tick[1]}" x2="{d0[0] + tick[0]}" y2="{d0[1] + tick[1]}"/>
    <line x1="{d1[0] - tick[0]}" y1="{d1[1] - tick[1]}" x2="{d1[0] + tick[0]}" y2="{d1[1] + tick[1]}"/>
  </g>
  </g>
</svg>
"""


def main():
    os.makedirs(ICONSET, exist_ok=True)
    for name, colors in THEMES.items():
        svg_path = os.path.join(HERE, f"AppIcon-{name}.svg")
        with open(svg_path, "w", encoding="utf-8") as f:
            f.write(svg(colors))
        png_path = os.path.join(ICONSET, f"AppIcon-{name}.png")
        subprocess.run(["rsvg-convert", "-w", "1024", "-h", "1024", "-b", "black", "-o", png_path, svg_path], check=True)
        print("wrote", png_path)


if __name__ == "__main__":
    main()
