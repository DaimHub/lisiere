#!/usr/bin/env python3
"""Extract closed contours from the approved monochrome concept images.

This reads pixels only; the SVG geometry is generated separately using Bloub's
closed Catmull-Rom routine. Requires Pillow. Run from the repository root.
"""
import json
import sys
from collections import deque
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'Resources' / 'Brand'
OUTPUT.mkdir(parents=True, exist_ok=True)
DIRECTIONS = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]


def components(mask, width, height):
    remaining = bytearray(mask)
    found = []
    for start in range(len(remaining)):
        if not remaining[start]:
            continue
        queue = deque([start])
        remaining[start] = 0
        region = set()
        while queue:
            p = queue.popleft()
            region.add(p)
            x, y = p % width, p // width
            for dx, dy in [(1, 0), (-1, 0), (0, 1), (0, -1)]:
                nx, ny = x + dx, y + dy
                if 0 <= nx < width and 0 <= ny < height:
                    n = ny * width + nx
                    if remaining[n]:
                        remaining[n] = 0
                        queue.append(n)
        if len(region) > 500:
            found.append(region)
    return sorted(found, key=len, reverse=True)


def contour(region, width):
    first = min(region)
    start = (first % width, first // width)
    point = start
    back = (point[0] - 1, point[1])
    result = []
    for _ in range(20000):
        result.append(point)
        index = DIRECTIONS.index((back[0] - point[0], back[1] - point[1]))
        for step in range(1, 9):
            d = (index + step) % 8
            dx, dy = DIRECTIONS[d]
            nxt = (point[0] + dx, point[1] + dy)
            if nxt[1] * width + nxt[0] in region:
                bx, by = DIRECTIONS[(d - 1) % 8]
                back = (point[0] + bx, point[1] + by)
                point = nxt
                break
        if point == start:
            break
    else:
        raise ValueError('Contour did not close')
    # Uniform samples keep cubic interpolation smooth without pixel stair steps.
    count = max(32, round(len(result) / 10))
    return [result[round(i * len(result) / count) % len(result)] for i in range(count)]


for mascot in json.loads((OUTPUT / 'mascots.json').read_text()):
    name = mascot['id']
    if len(sys.argv) > 1 and name not in sys.argv[1:]:
        continue
    source = ROOT / mascot['source']
    image = Image.open(source).convert('L')
    width, height = image.size
    black = bytearray(v < 128 for v in image.getdata())
    dark = components(black, width, height)
    light = components(bytearray(1 - v for v in black), width, height)
    assert len(dark) == 3 and len(light) == 3, (name, len(dark), len(light))
    scale = lambda points: [[round(x * 1024 / width, 2), round(y * 1024 / height, 2)] for x, y in points]
    data = {
        'source': str(source.relative_to(ROOT)),
        'body': [scale(contour(dark[0], width))],
        'eyes': [scale(contour(region, width)) for region in light[1:]],
        'pupils': [scale(contour(region, width)) for region in dark[1:]],
    }
    (OUTPUT / f'{name}.json').write_text(json.dumps(data, indent=2) + '\n')
    print(f'{name}: extracted body, eyes and pupils')
