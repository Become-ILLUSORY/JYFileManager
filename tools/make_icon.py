#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从设计稿生成 JY文件管理器 的 Android / Web 图标。

原则：**不改动原图**。整张设计稿直接使用，只做等比缩放。

关于自适应图标（Android 8+）的尺寸：
  画布 108dp，启动器只显示**中央 72dp**（= 画布的 2/3），外圈 18dp 是给视差/
  溢出用的，会被遮罩裁掉。所以前景不能铺满画布，否则设计稿里的文件夹会被
  圆形遮罩切掉角。
  这里让整张设计稿占据画布的 FG_FILL 倍并居中：
    - 大于 72/108 = 0.667  → 设计稿自带的圆角落在可见窗口之外，不会出现
      「框里还有一个框」的双圆角
    - 取 0.68 时，白色文件夹的最大半径约 137px < 可见圆半径 144px，
      即使启动器用**正圆**遮罩也不会切到文件夹（实测见 icon_preview）
"""
import os
import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(HERE, 'icon_source.png')
RES = os.path.join(ROOT, 'android/app/src/main/res')
WEB = os.path.join(ROOT, 'web/icons')

CANVAS = 432           # 108dp @ xxxhdpi
FG_FILL = 0.68         # 设计稿占画布比例（见上方说明）
LEGACY = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
DENS = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}


def load_art():
    """载入设计稿并裁到内容边界，再补成正方形（保持原样，不抠图）。"""
    im = Image.open(SRC).convert('RGBA')
    a = np.array(im)
    ys, xs = np.where(a[..., 3] > 8)
    art = im.crop((int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))
    side = max(art.size)
    sq = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    sq.paste(art, ((side - art.width) // 2, (side - art.height) // 2), art)
    return sq


def row_colors(art):
    """逐行取不透明像素的平均色，得到设计稿自身的竖向渐变。"""
    a = np.array(art).astype(float)
    rgb, al = a[..., :3], a[..., 3]
    rows = []
    for y in range(art.height):
        m = al[y] > 128
        rows.append(rgb[y][m].mean(axis=0) if m.any() else np.array([255.0, 255.0, 255.0]))
    col = np.zeros((art.height, 1, 3), dtype=np.uint8)
    for y, c in enumerate(rows):
        col[y, 0] = np.clip(c, 0, 255).astype(np.uint8)
    return Image.fromarray(col, 'RGB')


def bg_aligned(art, fill, canvas=CANVAS):
    """背景层：把设计稿的渐变**按前景同样的位置**拉伸到画布上。

    这样设计稿边缘处的颜色与背景完全一致，两者接缝不可见
    （若直接把渐变铺满画布，接缝处会有明显色带）。
    """
    col = row_colors(art)
    inner_h = max(1, int(round(canvas * fill)))
    band = col.resize((canvas, inner_h), Image.BILINEAR)
    out = Image.new('RGB', (canvas, canvas), (255, 255, 255))
    top = (canvas - inner_h) // 2
    out.paste(band, (0, top))
    if top > 0:
        bottom = canvas - top - inner_h
        out.paste(band.crop((0, 0, canvas, 1)).resize((canvas, top), Image.NEAREST), (0, 0))
        if bottom > 0:
            out.paste(
                band.crop((0, inner_h - 1, canvas, inner_h)).resize((canvas, bottom), Image.NEAREST),
                (0, top + inner_h),
            )
    return out


def art_on_canvas(art, fill, canvas=CANVAS):
    """把设计稿等比缩放并居中到画布上（超出部分裁掉）。"""
    k = canvas * fill / max(art.size)
    w, h = int(round(art.width * k)), int(round(art.height * k))
    r = art.resize((w, h), Image.LANCZOS)
    out = Image.new('RGBA', (canvas, canvas), (0, 0, 0, 0))
    out.paste(r, ((canvas - w) // 2, (canvas - h) // 2), r)
    return out


def monochrome_layer(art, fill, canvas=CANVAS):
    """主题图标（Monochrome）层：只保留设计稿里的白色文件夹轮廓。

    系统会用主题色给这层重新上色，所以只取 alpha（文件夹的形状），
    中间蓝色的 JY 镂空自然成为孔洞。
    """
    a = np.array(art.convert('RGBA'))
    rgb, al = a[..., :3].astype(int), a[..., 3]
    white = ((rgb.min(axis=2) > 190) & (al > 128)).astype(np.uint8) * 255
    m = Image.fromarray(white, 'L')
    k = canvas * fill / max(m.size)
    w, h = int(round(m.width * k)), int(round(m.height * k))
    m = m.resize((w, h), Image.LANCZOS)
    alpha = Image.new('L', (canvas, canvas), 0)
    alpha.paste(m, ((canvas - w) // 2, (canvas - h) // 2))
    out = Image.new('RGBA', (canvas, canvas), (255, 255, 255, 0))
    out.putalpha(alpha)
    return out


def mask_preview(comp, shape, canvas=CANVAS):
    """按启动器真实可见范围（中央 72dp）预览：shape = squircle | circle。"""
    d = canvas * 72 / 108.0
    box = [(canvas - d) / 2, (canvas - d) / 2, (canvas + d) / 2, (canvas + d) / 2]
    m = Image.new('L', (canvas, canvas), 0)
    dr = ImageDraw.Draw(m)
    if shape == 'circle':
        dr.ellipse(box, fill=255)
    else:
        dr.rounded_rectangle(box, radius=int(d * 0.26), fill=255)
    out = Image.new('RGBA', (canvas, canvas), (255, 255, 255, 255))
    out.paste(comp, (0, 0), m)
    return out


def main():
    art = load_art()
    print('设计稿裁切后：%dx%d' % art.size)

    fg = art_on_canvas(art, FG_FILL)
    bg = bg_aligned(art, FG_FILL)
    mono = monochrome_layer(art, FG_FILL)

    for d, size in DENS.items():
        dd = os.path.join(RES, 'mipmap-' + d)
        os.makedirs(dd, exist_ok=True)
        fg.resize((size, size), Image.LANCZOS).save(os.path.join(dd, 'ic_launcher_foreground.png'))
        bg.resize((size, size), Image.LANCZOS).save(os.path.join(dd, 'ic_launcher_background.png'))
        mono.resize((size, size), Image.LANCZOS).save(os.path.join(dd, 'ic_launcher_monochrome.png'))
        ls = LEGACY[d]
        # 传统图标：整张设计稿原样等比缩放，保留其自带圆角。
        # ic_launcher_round 也用同一张原图 —— 不做圆形，用户要的是原图。
        art.resize((ls, ls), Image.LANCZOS).save(os.path.join(dd, 'ic_launcher.png'))
        art.resize((ls, ls), Image.LANCZOS).save(os.path.join(dd, 'ic_launcher_round.png'))

    anydpi = os.path.join(RES, 'mipmap-anydpi-v26')
    os.makedirs(anydpi, exist_ok=True)
    xml = ('<?xml version="1.0" encoding="utf-8"?>\n'
           '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
           '    <background android:drawable="@mipmap/ic_launcher_background" />\n'
           '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
           '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />\n'
           '</adaptive-icon>\n')
    for n in ('ic_launcher.xml', 'ic_launcher_round.xml'):
        with open(os.path.join(anydpi, n), 'w') as f:
            f.write(xml)

    # Web
    os.makedirs(WEB, exist_ok=True)
    art.resize((512, 512), Image.LANCZOS).save(os.path.join(WEB, 'Icon-512.png'))
    art.resize((192, 192), Image.LANCZOS).save(os.path.join(WEB, 'Icon-192.png'))
    art.resize((192, 192), Image.LANCZOS).save(os.path.join(WEB, 'Icon-maskable-192.png'))
    art.resize((512, 512), Image.LANCZOS).save(os.path.join(WEB, 'Icon-maskable-512.png'))
    art.resize((64, 64), Image.LANCZOS).save(os.path.join(ROOT, 'web/favicon.png'))

    # 预览
    pv = os.path.join(HERE, 'icon_preview')
    os.makedirs(pv, exist_ok=True)
    art.resize((432, 432), Image.LANCZOS).save(os.path.join(pv, 'legacy.png'))
    comp = bg.convert('RGBA')
    comp.alpha_composite(fg)
    comp.save(os.path.join(pv, 'composed.png'))
    sq = mask_preview(comp, 'squircle')
    ci = mask_preview(comp, 'circle')
    sq.save(os.path.join(pv, 'squircle_preview.png'))
    ci.save(os.path.join(pv, 'circle_preview.png'))
    strip = Image.new('RGBA', (CANVAS * 3 + 40, CANVAS), (232, 232, 232, 255))
    for i, im in enumerate([art.resize((432, 432), Image.LANCZOS), sq, ci]):
        strip.paste(im, (i * (CANVAS + 20), 0), im)
    strip.save(os.path.join(pv, 'small_sizes.png'))

    print('OK -> 图标已生成（整图原样，圆角矩形）')


if __name__ == '__main__':
    main()
