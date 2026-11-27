#!/usr/bin/env python3
"""فاز ۸ — بند ۲: تولید آیکن‌های برند از یک PNG مرجع.

از یک تصویر مرجع (لوگوی شرکت — assets/logo/Hotel_ERP_Logo_2048.png) این
خروجی‌ها ساخته می‌شود:
  • ICO چنداندازه‌ای (16/32/48/64/128/256) برای ویندوز runner
    (apps/*/windows/runner/resources/app_icon.ico — بند ۶: آیکن نوار وظیفه)
  • PNGهای mipmap اندروید (48/72/96/144/192) برای ic_launcher APKها

استفاده:
  python tools/make_icons.py <source.png> [--out <dir>]

مثال:
  python tools/make_icons.py assets/logo/Hotel_ERP_Logo_2048.png

خروجی‌ها به‌صورت پیش‌فرض در build_icons/ نوشته می‌شوند؛ سپس می‌توانید فایل‌ها
را در جای خودشان کپی کنید. وابستگی: pip install pillow
"""

import argparse
import os
from pathlib import Path

from PIL import Image

# اندازه‌های استاندارد ICO ویندوز (بند ۲ — شامل 256 برای آیکن بزرگ اکسپلورر)
ICO_SIZES = [16, 32, 48, 64, 128, 256]

# اندازه‌های استاندارد mipmap اندروید — نام پوشه → اندازه پیکسل
MIPMAP_SIZES = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
}


def make_icons(source: Path, out_dir: Path) -> None:
    img = Image.open(source).convert('RGBA')
    if img.width != img.height:
        # مربع‌سازی با کادر مرکزی — لوگوی برند باید مربع باشد
        side = min(img.width, img.height)
        left = (img.width - side) // 2
        top = (img.height - side) // 2
        img = img.crop((left, top, left + side, top + side))

    out_dir.mkdir(parents=True, exist_ok=True)

    # ۱) ICO چنداندازه‌ای — همه اندازه‌ها داخل یک فایل
    frames = [img.resize((s, s), Image.LANCZOS) for s in ICO_SIZES]
    ico_path = out_dir / 'app_icon.ico'
    frames[-1].save(ico_path, format='ICO', sizes=[(s, s) for s in ICO_SIZES],
                    append_images=frames[:-1])
    print(f'ICO: {ico_path} ({os.path.getsize(ico_path)} bytes)')

    # ۲) mipmapهای اندروید
    for dpi, size in MIPMAP_SIZES.items():
        d = out_dir / f'mipmap-{dpi}'
        d.mkdir(parents=True, exist_ok=True)
        resized = img.resize((size, size), Image.LANCZOS)
        dest = d / 'ic_launcher.png'
        resized.save(dest, format='PNG')
        print(f'mipmap: {dest} ({size}x{size})')

    # ۳) نسخه playstore (512) — برای مارکت/xxxhdpi
    play = out_dir / 'playstore'
    play.mkdir(parents=True, exist_ok=True)
    dest = play / 'ic_launcher.png'
    img.resize((512, 512), Image.LANCZOS).save(dest, format='PNG')
    print(f'playstore: {dest} (512x512)')


def main() -> None:
    parser = argparse.ArgumentParser(description='تولید ICO + mipmap از PNG برند')
    parser.add_argument('source', type=Path, help='PNG مرجع (لوگو، مربع ترجیحاً)')
    parser.add_argument('--out', type=Path, default=Path('build_icons'),
                        help='پوشه خروجی (پیش‌فرض build_icons/)')
    args = parser.parse_args()
    if not args.source.is_file():
        raise SystemExit(f'فایل مرجع یافت نشد: {args.source}')
    make_icons(args.source, args.out)


if __name__ == '__main__':
    main()
