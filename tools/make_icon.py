#!/usr/bin/env python3
"""从设计稿生成 Android 自适应图标 + 传统图标 + Web 图标。

- 前景层：从原图抠出白色文件夹（去掉蓝色底板），放在 108dp 画布的安全区内
- 背景层：由原图蓝色底板扩散填充出的满幅渐变（108dp 出血）
- 传统图标：整幅圆角方形设计稿（供 Android 8 以下 / Web 使用）
"""
import os
import sys
import numpy as np
from PIL import Image, ImageFilter

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'icon_source.png')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, 'android/app/src/main/res')
WEB = os.path.join(ROOT, 'web/icons')

# 自适应图标：108dp 画布，可见安全区为中央 72dp（66.7%）
CANVAS = 432          # xxxhdpi 108dp
FG_FRACTION = 0.72    # 前景（文件夹）占画布比例，落在安全区内
LEGACY_FRACTION = 0.99  # 传统图标里设计稿几乎铺满画布


def sq_bbox(alpha, thr=128):
    op = alpha > thr
    ys, xs = np.where(op)
    return xs.min(), xs.max(), ys.min(), ys.max()


def extract_foreground(crop):
    """返回 (rgba 前景, alpha 浮点) —— 白色文件夹 / JY 镂空 / 小锁。"""
    r, g, b = crop[..., 0], crop[..., 1], crop[..., 2]
    blueness = b - np.maximum(r, g)
    lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
    # 蓝色底板的 blueness 约 120-210，白色文件夹约 0-30
    t = np.clip((95.0 - blueness) / 75.0, 0.0, 1.0)
    # 亮度门限：把蓝色边缘的抗锯齿、深色阴影排除
    t *= np.clip((lum - 0.30) / 0.18, 0.0, 1.0)
    a = t * (crop[..., 3] / 255.0)
    out = crop.copy()
    out[..., 3] = np.clip(a * 255.0, 0, 255)
    return out, a


def build_background(crop, fg_alpha):
    """把前景区域挖掉后用归一化高斯模糊扩散填充，得到满幅蓝色渐变。"""
    S = 160
    small = np.array(
        Image.fromarray(crop[..., :3].astype(np.uint8)).resize((S, S), Image.LANCZOS)
    ).astype(np.float32)
    m = np.array(
        Image.fromarray((fg_alpha * 255).astype(np.uint8)).resize((S, S), Image.LANCZOS)
    ).astype(np.float32) / 255.0
    data = np.where((m > 0.12)[..., None], np.nan, small)

    for radius in (10, 24, 52, 90):
        if not np.isnan(data).any():
            break
        vals = np.nan_to_num(data, nan=0.0)
        msk = (~np.isnan(data)).astype(np.float32)
        v = np.array(
            Image.fromarray(np.clip(vals, 0, 255).astype(np.uint8))
            .filter(ImageFilter.GaussianBlur(radius))
        ).astype(np.float32)
        mm = np.array(
            Image.fromarray((msk * 255).astype(np.uint8))
            .filter(ImageFilter.GaussianBlur(radius))
        ).astype(np.float32) / 255.0
        filled = v / np.maximum(mm, 1e-3)
        data = np.where(np.isnan(data), filled, data)

    data = np.nan_to_num(data, nan=0.0)
    img = Image.fromarray(np.clip(data, 0, 255).astype(np.uint8))
    return img.filter(ImageFilter.GaussianBlur(3))


def fit_center(src, fraction, canvas):
    """把 src 缩放到「占画布 fraction 比例」并居中（fraction 相对画布边长）。"""
    longest = max(src.width, src.height)
    target = max(1, int(round(canvas * fraction)))
    k = target / float(longest)
    w = max(1, int(round(src.width * k)))
    h = max(1, int(round(src.height * k)))
    r = src.resize((w, h), Image.LANCZOS)
    out = Image.new('RGBA', (canvas, canvas), (0, 0, 0, 0))
    out.paste(r, ((canvas - w) // 2, (canvas - h) // 2), r)
    return out


def main():
    im = Image.open(SRC).convert('RGBA')
    arr = np.array(im).astype(np.float32)
    x0, x1, y0, y1 = sq_bbox(arr[..., 3])
    pad = 4
    crop = arr[max(0, y0 - pad):y1 + pad + 1, max(0, x0 - pad):x1 + pad + 1]
    print('squircle bbox', x0, x1, y0, y1, '-> crop', crop.shape[1], crop.shape[0])

    fg, fg_alpha = extract_foreground(crop)
    fg_img = Image.fromarray(fg.astype(np.uint8))
    bg_small = build_background(crop, fg_alpha)

    # ---- 背景层（108dp 出血，铺满画布）----
    bg = bg_small.resize((CANVAS, CANVAS), Image.LANCZOS).convert('RGBA')

    # ---- 前景层（居中，缩到安全区）----
    fg_layer = fit_center(fg_img, FG_FRACTION, CANVAS)

    # ---- 传统图标（整幅设计稿）----
    legacy_src = Image.fromarray(crop.astype(np.uint8))
    legacy = fit_center(legacy_src, LEGACY_FRACTION, CANVAS)

    out_dir = os.path.join(ROOT, 'tools/icon_preview')
    os.makedirs(out_dir, exist_ok=True)
    bg.save(f'{out_dir}/bg.png')
    fg_layer.save(f'{out_dir}/fg.png')
    legacy.save(f'{out_dir}/legacy.png')
    # 预览合成（圆形蒙版，模拟系统裁剪）
    comp = Image.alpha_composite(bg, fg_layer)
    comp.save(f'{out_dir}/composed.png')
    mask = Image.new('L', (CANVAS, CANVAS), 0)
    from PIL import ImageDraw
    ImageDraw.Draw(mask).ellipse((0, 0, CANVAS, CANVAS), fill=255)
    circle = comp.copy()
    circle.putalpha(mask)
    circle.save(f'{out_dir}/circle_preview.png')

    densities = {
        'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432,
    }
    legacy_sizes = {
        'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192,
    }

    bg_full = bg_small.resize((CANVAS, CANVAS), Image.LANCZOS).convert('RGB')

    for d, size in densities.items():
        d_dir = os.path.join(RES, f'mipmap-{d}')
        os.makedirs(d_dir, exist_ok=True)
        fg_layer.resize((size, size), Image.LANCZOS).save(
            os.path.join(d_dir, 'ic_launcher_foreground.png'))
        bg_full.resize((size, size), Image.LANCZOS).save(
            os.path.join(d_dir, 'ic_launcher_background.png'))
        ls = legacy_sizes[d]
        legacy.resize((ls, ls), Image.LANCZOS).save(
            os.path.join(d_dir, 'ic_launcher.png'))
        circle.resize((ls, ls), Image.LANCZOS).save(
            os.path.join(d_dir, 'ic_launcher_round.png'))

    anydpi = os.path.join(RES, 'mipmap-anydpi-v26')
    os.makedirs(anydpi, exist_ok=True)
    xml = '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
'''
    for name in ('ic_launcher.xml', 'ic_launcher_round.xml'):
        with open(os.path.join(anydpi, name), 'w') as f:
            f.write(xml)

    os.makedirs(WEB, exist_ok=True)
    legacy.resize((192, 192), Image.LANCZOS).save(os.path.join(WEB, 'Icon-192.png'))
    legacy.resize((512, 512), Image.LANCZOS).save(os.path.join(WEB, 'Icon-512.png'))
    legacy.resize((192, 192), Image.LANCZOS).save(os.path.join(WEB, 'Icon-maskable-192.png'))
    legacy.resize((512, 512), Image.LANCZOS).save(os.path.join(WEB, 'Icon-maskable-512.png'))
    legacy.resize((64, 64), Image.LANCZOS).save(os.path.join(ROOT, 'web/favicon.png'))

    print('OK -> icons written')


if __name__ == '__main__':
    sys.exit(main())
