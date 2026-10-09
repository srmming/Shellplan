"""
把手机原始截图（AppStore/raw/<语言>/<界面>.png）合成为 App Store 宣传图：
蓝色背景 + 顶部标题 + 圆角截图，尺寸 1320 × 2868（iPhone 6.9 寸）。
输出到 AppStore/screenshots/<语言>/1.png … 6.png，简体中文那套另外复制到 docs/assets/screenshots/ 给网站和 README 用。

用法：python3 Design/make_screenshots.py
"""

import base64
import os
import subprocess
from xml.sax.saxutils import escape

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
RAW = os.path.join(ROOT, "AppStore", "raw")
OUT = os.path.join(ROOT, "AppStore", "screenshots")
SITE = os.path.join(ROOT, "docs", "assets", "screenshots")

W, H = 1320, 2868
SCREENS = ["home", "model", "plan", "door", "note", "export"]

# 每张图的标题（一到两行）
CAPTIONS = {
    "zh-Hans": [["一间一间扫", "自动拼成全屋"], ["空房间白模", "尺寸自动标好"], ["带尺寸的平面图"], ["门窗样式和位置", "随手就能改"],
                ["备注、照片、测距", "还能填实测值"], ["一键导出", "交给 AI 和 Blender"]],
    "zh-Hant": [["一間一間掃", "自動拼成全屋"], ["空房間白模", "尺寸自動標好"], ["帶尺寸的平面圖"], ["門窗樣式和位置", "隨手就能改"],
                ["備註、照片、測距", "還能填實測值"], ["一鍵匯出", "交給 AI 和 Blender"]],
    "en": [["Scan room by room,", "get the whole home"], ["Empty 3D model,", "dimensions included"], ["Dimensioned", "floor plan"], ["Edit doors", "and windows"],
           ["Notes, photos", "and measurements"], ["Export for", "AI and Blender"]],
    "es": [["Escanea por", "habitaciones"], ["Modelo 3D vacío", "con medidas"], ["Plano", "con medidas"], ["Edita puertas", "y ventanas"],
           ["Notas, fotos", "y mediciones"], ["Exporta para", "IA y Blender"]],
    "ja": [["部屋ごとにスキャン", "家全体の間取りに"], ["家具のない白モデル", "寸法つき"], ["寸法入りの平面図"], ["ドアと窓の種類や", "位置を編集"],
           ["メモ・写真・計測", "実測値も入力"], ["AI と Blender へ", "ワンタップで書き出し"]],
}

FONT = "PingFang SC, Hiragino Sans, Helvetica Neue, sans-serif"


def compose(lang, index, screen):
    raw = os.path.join(RAW, lang, f"{screen}.png")
    if not os.path.exists(raw):
        return None
    # 截图直接嵌进 SVG：路径里有空格或中文时，rsvg-convert 读不到 file:// 链接
    with open(raw, "rb") as f:
        data = base64.b64encode(f.read()).decode()
    lines = CAPTIONS[lang][index]
    size = 104
    top = 300 if len(lines) == 2 else 360
    text = "".join(
        f'<text x="{W / 2}" y="{top + i * size * 1.22:.0f}" text-anchor="middle" font-family="{FONT}" '
        f'font-size="{size}" font-weight="700" fill="#FFFFFF">{escape(line)}</text>'
        for i, line in enumerate(lines))
    sw = 1056
    sh = round(sw * 2868 / 1320)
    sx, sy = (W - sw) // 2, 560
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="{W}" height="{H}">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#3B82F6"/>
      <stop offset="1" stop-color="#1E3A8A"/>
    </linearGradient>
    <clipPath id="screen"><rect x="{sx}" y="{sy}" width="{sw}" height="{sh}" rx="72"/></clipPath>
  </defs>
  <rect width="{W}" height="{H}" fill="url(#bg)"/>
  {text}
  <rect x="{sx - 10}" y="{sy - 10}" width="{sw + 20}" height="{sh + 20}" rx="82" fill="#0B1220" opacity="0.35"/>
  <image x="{sx}" y="{sy}" width="{sw}" height="{sh}" clip-path="url(#screen)" xlink:href="data:image/png;base64,{data}"/>
</svg>'''
    out_dir = os.path.join(OUT, lang)
    os.makedirs(out_dir, exist_ok=True)
    svg_path = os.path.join(out_dir, f"{index + 1}.svg")
    png_path = os.path.join(out_dir, f"{index + 1}.png")
    with open(svg_path, "w", encoding="utf-8") as f:
        f.write(svg)
    subprocess.run(["rsvg-convert", "-w", str(W), "-h", str(H), "-b", "#1E3A8A", "-o", png_path, svg_path], check=True)
    os.remove(svg_path)
    return png_path


def main():
    made = 0
    for lang in CAPTIONS:
        for i, screen in enumerate(SCREENS):
            if compose(lang, i, screen):
                made += 1
    os.makedirs(SITE, exist_ok=True)
    for i in range(len(SCREENS)):
        src = os.path.join(OUT, "zh-Hans", f"{i + 1}.png")
        if os.path.exists(src):
            subprocess.run(["sips", "-Z", "900", src, "--out", os.path.join(SITE, f"{i + 1}.png")],
                           check=True, capture_output=True)
    print(f"合成了 {made} 张")


if __name__ == "__main__":
    main()
