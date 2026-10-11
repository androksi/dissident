#!/usr/bin/env python3
"""Writes the list of wallpapers (name, file, size, width, height) as JSON.

Usage: python3 web/wallpapers-index.py wallpapers > _site/wallpapers/index.json
Reads image sizes from the PNG/JPEG headers, so it needs no extra packages.
"""
import json
import os
import struct
import sys


def image_size(path):
    with open(path, 'rb') as f:
        head = f.read(26)
        if head[:8] == b'\x89PNG\r\n\x1a\n':
            return struct.unpack('>II', head[16:24])
        if head[:2] == b'\xff\xd8':                      # JPEG: walk the segments until a SOF marker
            f.seek(2)
            while True:
                marker = f.read(2)
                if len(marker) < 2 or marker[0] != 0xFF:
                    break
                if marker[1] in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                    f.read(3)
                    h, w = struct.unpack('>HH', f.read(4))
                    return w, h
                length = struct.unpack('>H', f.read(2))[0]
                f.seek(length - 2, 1)
    return 0, 0


folder = sys.argv[1]
items = []
for name in sorted(os.listdir(folder)):
    path = os.path.join(folder, name)
    if not os.path.isfile(path) or not name.lower().endswith(('.jpg', '.jpeg', '.png')):
        continue
    w, h = image_size(path)
    items.append({'name': os.path.splitext(name)[0], 'file': name, 'size': os.path.getsize(path), 'width': w, 'height': h})
json.dump(items, sys.stdout, indent=2)
print()
