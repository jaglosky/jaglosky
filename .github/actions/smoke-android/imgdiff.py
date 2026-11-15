"""Before / after screenshot comparison with no dependencies (pure standard library PNG decode / encode).

Usage: python3 -I imgdiff.py <before.png> <after.png> <diff.png>
Prints the share of pixels that differ, e.g. "0.42". The top 5 % of the screen (status bar: clock, icons) is
ignored. The diff image is the "after" screenshot dimmed, with every changed pixel in red.
Supports what `adb screencap -p` and `simctl io screenshot` write: 8-bit RGB / RGBA, not interlaced.
"""
import struct
import sys
import zlib

THRESHOLD = 24  # per-channel difference that counts as "changed" (anti-aliasing and compression noise stay below)


def read_png(path):
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path}: not a PNG")
    pos, idat, width, height, bpp = 8, [], 0, 0, 0
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos : pos + 8])
        chunk = data[pos + 8 : pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, color, _, _, interlace = struct.unpack(">IIBBBBB", chunk)
            if depth != 8 or color not in (2, 6) or interlace:
                raise ValueError(f"{path}: unsupported PNG (depth {depth}, colour type {color}, interlace {interlace})")
            bpp = 3 if color == 2 else 4
        elif kind == b"IDAT":
            idat.append(chunk)
        pos += 12 + length
    raw = zlib.decompress(b"".join(idat))
    stride = width * bpp
    rows, prev = [], bytearray(stride)
    for y in range(height):
        start = y * (stride + 1)
        f = raw[start]
        line = bytearray(raw[start + 1 : start + 1 + stride])
        if f == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 255
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif f == 3:
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 255
        elif f == 4:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(line)
        prev = line
    return width, height, bpp, rows


def write_png(path, width, height, rows):
    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    raw = b"".join(b"\x00" + bytes(r) for r in rows)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


def main(before, after, out):
    wa, ha, ba, ra = read_png(before)
    wb, hb, bb, rb = read_png(after)
    if (wa, ha) != (wb, hb):
        print("100.00")  # different screen sizes (e.g. rotation) — nothing to align
        return
    skip = int(ha * 0.05)
    changed, total, out_rows = 0, 0, []
    for y in range(ha):
        a, b = ra[y], rb[y]
        row = bytearray(wa * 3)
        same_line = y < skip or a == b if ba == bb else False
        for x in range(wa):
            r, g, bl = b[x * bb], b[x * bb + 1], b[x * bb + 2]
            if same_line:
                diff = False
            else:
                diff = y >= skip and (abs(r - a[x * ba]) > THRESHOLD or abs(g - a[x * ba + 1]) > THRESHOLD or abs(bl - a[x * ba + 2]) > THRESHOLD)
            if diff:
                changed += 1
                row[x * 3 : x * 3 + 3] = b"\xff\x1e\x1e"
            else:
                grey = (r * 30 + g * 59 + bl * 11) // 100
                dim = 255 - (255 - grey) // 3  # washed-out copy of the "after" screen as context
                row[x * 3 : x * 3 + 3] = bytes((dim, dim, dim))
        if y >= skip:
            total += wa
        out_rows.append(row)
    write_png(out, wa, ha, out_rows)
    print(f"{100.0 * changed / max(total, 1):.2f}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3])
