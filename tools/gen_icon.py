#!/usr/bin/env python3
"""生成四象限待办的应用图标（纯标准库实现，无第三方依赖）。

用法：
    python3 tools/gen_icon.py

产物：
    AppScope/resources/base/media/app_icon.png
    entry/src/main/resources/base/media/app_icon.png
    entry/src/main/resources/base/media/startIcon.png
"""

import os
import struct
import zlib

SIZE = 1024
BG = (0x17, 0x19, 0x1D)
TILES = [
    (0xF8, 0x71, 0x71),  # 重要紧急
    (0x60, 0xA5, 0xFA),  # 重要不紧急
    (0xFB, 0xBF, 0x24),  # 紧急不重要
    (0x94, 0xA3, 0xB8),  # 不重要不紧急
]

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def blend(dst, offset, color, alpha):
    if alpha <= 0:
        return
    sr, sg, sb = color
    dr, dg, db, da = dst[offset], dst[offset + 1], dst[offset + 2], dst[offset + 3]
    na = alpha + da * (1 - alpha)
    if na <= 0:
        dst[offset] = dst[offset + 1] = dst[offset + 2] = dst[offset + 3] = 0
        return
    dst[offset] = int((sr * alpha + dr * da * (1 - alpha)) / na)
    dst[offset + 1] = int((sg * alpha + dg * da * (1 - alpha)) / na)
    dst[offset + 2] = int((sb * alpha + db * da * (1 - alpha)) / na)
    dst[offset + 3] = int(na)


def coverage(x, y, x0, y0, x1, y1, radius):
    if x < x0 or x > x1 or y < y0 or y > y1:
        return 0.0
    cx = min(max(x, x0 + radius), x1 - radius)
    cy = min(max(y, y0 + radius), y1 - radius)
    dx, dy = x - cx, y - cy
    dist = (dx * dx + dy * dy) ** 0.5
    cov = radius - dist + 0.5
    if cov <= 0:
        return 0.0
    return 1.0 if cov >= 1 else cov


def round_rect(buf, x0, y0, x1, y1, radius, color, size=SIZE):
    for y in range(int(y0) - 1, int(y1) + 2):
        if y < 0 or y >= size:
            continue
        for x in range(int(x0) - 1, int(x1) + 2):
            if x < 0 or x >= size:
                continue
            cov = coverage(x + 0.5, y + 0.5, x0, y0, x1, y1, radius)
            if cov > 0:
                blend(buf, (y * size + x) * 4, color, cov)


def write_png(path, width, height, buf):
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)
        raw += buf[y * stride:(y + 1) * stride]

    def chunk(tag, data):
        return (struct.pack('>I', len(data)) + tag + data +
                struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = b'\x89PNG\r\n\x1a\n'
    png += chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(bytes(raw), 9))
    png += chunk(b'IEND', b'')
    with open(path, 'wb') as f:
        f.write(png)


def build_icon():
    buf = bytearray(SIZE * SIZE * 4)
    pad = 96
    radius = 200
    round_rect(buf, pad, pad, SIZE - pad, SIZE - pad, radius, BG)

    inner_pad = 186
    gap = 44
    span = (SIZE - inner_pad * 2 - gap) // 2
    tile_radius = 92
    for index, color in enumerate(TILES):
        col = index % 2
        row = index // 2
        x0 = inner_pad + col * (span + gap)
        y0 = inner_pad + row * (span + gap)
        round_rect(buf, x0, y0, x0 + span, y0 + span, tile_radius, color)
    return buf


def main():
    buf = build_icon()
    targets = [
        os.path.join(ROOT, 'AppScope/resources/base/media/app_icon.png'),
        os.path.join(ROOT, 'entry/src/main/resources/base/media/app_icon.png'),
        os.path.join(ROOT, 'entry/src/main/resources/base/media/startIcon.png'),
    ]
    for path in targets:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        write_png(path, SIZE, SIZE, buf)
        print('wrote', path)


if __name__ == '__main__':
    main()
