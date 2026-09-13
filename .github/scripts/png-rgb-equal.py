#!/usr/bin/env python3
"""Compare the decoded pixels of two 8-bit, non-interlaced RGB/RGBA PNGs (stdlib only)."""
import struct
import sys
import zlib


def decode(path):
    data = open(path, 'rb').read()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', f'{path}: not a PNG'
    pos, idat, header = 8, b'', None
    while pos < len(data):
        length, kind = struct.unpack('>I4s', data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b'IHDR':
            header = struct.unpack('>IIBBBBB', body)
        elif kind == b'IDAT':
            idat += body
        elif kind == b'IEND':
            break
    width, height, depth, color, _, _, interlace = header
    assert depth == 8 and interlace == 0 and color in (2, 6), f'{path}: unsupported PNG format'
    bpp = 3 if color == 2 else 4
    raw, stride = zlib.decompress(idat), width * bpp
    prev, rows = bytearray(stride), []
    for y in range(height):
        start = y * (stride + 1)
        filt, row = raw[start], bytearray(raw[start + 1:start + 1 + stride])
        for i in range(stride):
            a = row[i - bpp] if i >= bpp else 0
            b, c = prev[i], prev[i - bpp] if i >= bpp else 0
            if filt == 1:
                row[i] = (row[i] + a) & 255
            elif filt == 2:
                row[i] = (row[i] + b) & 255
            elif filt == 3:
                row[i] = (row[i] + (a + b) // 2) & 255
            elif filt == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                row[i] = (row[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(bytes(row) if bpp == 3 else bytes(v for i, v in enumerate(row) if i % 4 != 3))
        prev = row
    return width, height, b''.join(rows)


if __name__ == '__main__':
    left, right = decode(sys.argv[1]), decode(sys.argv[2])
    if left != right:
        raise SystemExit(f'Pixel mismatch: {sys.argv[1]} vs {sys.argv[2]}')
    print(f'Pixels identical ({left[0]}x{left[1]}): {sys.argv[1]} == {sys.argv[2]}')
