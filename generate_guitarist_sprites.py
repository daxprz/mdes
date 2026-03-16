#!/usr/bin/env python3
"""Generate guitarist character sprites."""

from PIL import Image, ImageDraw
import os

OUT = "/Users/jeremy/dev/dax/test123/assets/sprites/characters"
os.makedirs(OUT, exist_ok=True)

# Color palette helpers
def shade(base, factor):
    return tuple(max(0, min(255, int(c * factor))) for c in base)

def pal(base_color):
    return (
        shade(base_color, 1.35),
        base_color,
        shade(base_color, 0.65),
        shade(base_color, 0.40),
    )

BLACK = (20, 20, 25)
OUTLINE = (15, 15, 20)
SKIN = (235, 195, 155)
SKIN_SHADOW = (200, 160, 120)
SKIN_DEEP = (170, 130, 95)
WHITE_EYE = (255, 255, 255)
PUPIL = (30, 30, 40)
TRANSP = (0, 0, 0, 0)

# Guitarist colors - rock star golden/red/black
GUITAR_GOLD = (220, 180, 50)
GUITAR_RED = (200, 50, 60)
GUITAR_BLACK = (40, 35, 45)
JACKET_PURPLE = (120, 50, 160)
PANTS_BLACK = (35, 30, 40)
HAIR_WILD = (180, 60, 40)

GG = pal(GUITAR_GOLD)
GR = pal(GUITAR_RED)
GB = pal(GUITAR_BLACK)
JP = pal(JACKET_PURPLE)
PB = pal(PANTS_BLACK)
HW = pal(HAIR_WILD)

def px(img, x, y, color):
    if 0 <= x < img.width and 0 <= y < img.height:
        if len(color) == 3:
            color = color + (255,)
        img.putpixel((x, y), color)

def fill_rect(img, x0, y0, w, h, color):
    for yy in range(y0, y0 + h):
        for xx in range(x0, x0 + w):
            px(img, xx, yy, color)

def draw_eyes(img, cx, cy, direction="down"):
    if direction == "down":
        px(img, cx - 2, cy, WHITE_EYE)
        px(img, cx - 1, cy, PUPIL)
        px(img, cx + 1, cy, WHITE_EYE)
        px(img, cx + 2, cy, PUPIL)
    elif direction == "left":
        px(img, cx - 1, cy, WHITE_EYE)
        px(img, cx, cy, PUPIL)
    elif direction == "right":
        px(img, cx, cy, WHITE_EYE)
        px(img, cx + 1, cy, PUPIL)

def apply_outline(img):
    w, h = img.size
    outline_img = Image.new("RGBA", (w, h), TRANSP)
    pixels = img.load()
    out_px = outline_img.load()
    for y in range(h):
        for x in range(w):
            if pixels[x, y][3] > 0:
                continue
            for dx, dy in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and pixels[nx, ny][3] > 0:
                    out_px[x, y] = OUTLINE + (255,)
                    break
    result = Image.new("RGBA", (w, h), TRANSP)
    result.paste(outline_img, (0, 0))
    result.paste(img, (0, 0), img)
    return result

# ---------------------------------------------------------------------------
# Side-view sprite (192x32, 6 frames of 32x32)
# Frame layout: 0=idle, 1=walk1, 2=walk2, 3=jump, 4=attack1, 5=attack2
# ---------------------------------------------------------------------------

def draw_guitarist_side(img, frame_idx):
    y_off = -3 if frame_idx == 3 else 0

    # Legs/pants
    if frame_idx == 1:
        fill_rect(img, 11, 24 + y_off, 3, 6, PB[1])
        fill_rect(img, 18, 23 + y_off, 3, 6, PB[1])
    elif frame_idx == 2:
        fill_rect(img, 13, 23 + y_off, 3, 6, PB[1])
        fill_rect(img, 16, 24 + y_off, 3, 6, PB[1])
    else:
        fill_rect(img, 12, 24 + y_off, 3, 6, PB[1])
        fill_rect(img, 17, 24 + y_off, 3, 6, PB[1])

    # Boots
    fill_rect(img, 11, 28 + y_off, 4, 2, PB[2])
    fill_rect(img, 17, 28 + y_off, 4, 2, PB[2])

    # Body - purple rock jacket
    fill_rect(img, 10, 14 + y_off, 12, 10, JP[1])
    fill_rect(img, 10, 14 + y_off, 12, 3, JP[0])
    fill_rect(img, 10, 21 + y_off, 12, 3, JP[2])
    # Jacket opening / gold trim
    fill_rect(img, 15, 15 + y_off, 2, 7, GG[1])
    px(img, 15, 15 + y_off, GG[0])

    # Belt with gold buckle
    fill_rect(img, 10, 22 + y_off, 12, 2, PB[2])
    fill_rect(img, 14, 22 + y_off, 4, 2, GG[1])

    # Wild red/orange hair
    fill_rect(img, 9, 4 + y_off, 13, 7, HW[1])
    fill_rect(img, 9, 4 + y_off, 13, 2, HW[0])
    fill_rect(img, 9, 9 + y_off, 13, 2, HW[2])
    # Spiky hair tips
    px(img, 8, 5 + y_off, HW[0])
    px(img, 22, 4 + y_off, HW[0])
    px(img, 21, 3 + y_off, HW[1])
    px(img, 10, 3 + y_off, HW[1])
    px(img, 13, 2 + y_off, HW[0])

    # Face
    fill_rect(img, 10, 8 + y_off, 6, 6, SKIN)
    fill_rect(img, 10, 12 + y_off, 6, 2, SKIN_SHADOW)
    draw_eyes(img, 12, 10 + y_off, "left")
    # Confident grin
    px(img, 11, 12 + y_off, (180, 80, 80))

    # Guitar
    if frame_idx in (4, 5):
        # Attack - guitar swung forward, strumming
        fill_rect(img, 3, 16 + y_off, 2, 12, GG[2])  # neck
        fill_rect(img, 1, 18 + y_off, 6, 6, GR[1])    # body
        fill_rect(img, 2, 19 + y_off, 4, 4, GR[0])
        px(img, 3, 21 + y_off, GG[0])                   # sound hole
        px(img, 4, 21 + y_off, GG[0])
        # Strumming hand
        fill_rect(img, 5, 18 + y_off, 3, 2, SKIN)
        if frame_idx == 5:
            # Musical note particles
            px(img, 0, 14 + y_off, GG[0])
            px(img, 2, 12 + y_off, (100, 200, 255))
    else:
        # Idle/walk - guitar held at side
        fill_rect(img, 6, 12 + y_off, 2, 14, GG[2])   # neck
        fill_rect(img, 4, 20 + y_off, 6, 6, GR[1])    # body
        fill_rect(img, 5, 21 + y_off, 4, 4, GR[0])
        px(img, 6, 23 + y_off, GG[0])                   # sound hole
        # Headstock
        fill_rect(img, 5, 11 + y_off, 4, 2, GG[1])
        px(img, 5, 10 + y_off, GG[0])
        px(img, 8, 10 + y_off, GG[0])


# ---------------------------------------------------------------------------
# Top-down sprite (128x128, 4x4 grid of 32x32)
# Rows: down, left, right, up.  Cols: idle, walk1, walk2, walk3
# ---------------------------------------------------------------------------

def draw_guitarist_topdown(img, direction, phase):
    cx, cy = 15, 15
    leg_offset = [-1, 0, 1, 0][phase]

    if direction == "down":
        # Legs
        fill_rect(img, 11, 22, 4, 6, PB[1])
        fill_rect(img, 17, 22, 4, 6, PB[1])
        if phase in (1, 3):
            fill_rect(img, 11, 22 + leg_offset, 4, 6, PB[1])
        fill_rect(img, 11, 26, 4, 2, PB[2])
        fill_rect(img, 17, 26, 4, 2, PB[2])
        # Body
        fill_rect(img, 10, 12, 12, 11, JP[1])
        fill_rect(img, 10, 12, 12, 3, JP[0])
        fill_rect(img, 10, 20, 12, 3, JP[2])
        # Gold trim
        fill_rect(img, 15, 13, 2, 8, GG[1])
        # Belt
        fill_rect(img, 10, 21, 12, 2, PB[2])
        fill_rect(img, 14, 21, 4, 2, GG[1])
        # Hair
        fill_rect(img, 10, 4, 12, 9, HW[1])
        fill_rect(img, 10, 4, 12, 3, HW[0])
        fill_rect(img, 10, 10, 12, 3, HW[2])
        # Spiky
        px(img, 9, 5, HW[0])
        px(img, 22, 4, HW[0])
        px(img, 14, 2, HW[0])
        px(img, 18, 3, HW[1])
        # Face
        fill_rect(img, 12, 9, 8, 4, SKIN)
        fill_rect(img, 12, 11, 8, 2, SKIN_SHADOW)
        draw_eyes(img, 15, 10, "down")
        # Guitar (right side)
        fill_rect(img, 23, 8, 2, 12, GG[2])
        fill_rect(img, 22, 16, 4, 5, GR[1])
        fill_rect(img, 22, 17, 4, 3, GR[0])
        px(img, 24, 18, GG[0])

    elif direction == "up":
        fill_rect(img, 11, 22, 4, 6, PB[1])
        fill_rect(img, 17, 22, 4, 6, PB[1])
        fill_rect(img, 11, 26, 4, 2, PB[2])
        fill_rect(img, 17, 26, 4, 2, PB[2])
        fill_rect(img, 10, 12, 12, 11, JP[1])
        fill_rect(img, 10, 12, 12, 3, JP[0])
        fill_rect(img, 10, 20, 12, 3, JP[2])
        fill_rect(img, 10, 21, 12, 2, PB[2])
        fill_rect(img, 14, 21, 4, 2, GG[1])
        # Hair from behind - wild spikes
        fill_rect(img, 10, 4, 12, 9, HW[1])
        fill_rect(img, 10, 4, 12, 3, HW[0])
        fill_rect(img, 10, 10, 12, 3, HW[2])
        px(img, 9, 5, HW[0])
        px(img, 22, 4, HW[0])
        px(img, 14, 2, HW[0])
        px(img, 18, 3, HW[1])
        px(img, 11, 3, HW[1])
        # Guitar on back
        fill_rect(img, 7, 8, 2, 12, GG[2])
        fill_rect(img, 6, 16, 4, 5, GR[1])

    elif direction == "left":
        fill_rect(img, 12, 22, 4, 6, PB[1])
        fill_rect(img, 16, 22, 4, 6, PB[1])
        fill_rect(img, 12, 26, 4, 2, PB[2])
        fill_rect(img, 16, 26, 4, 2, PB[2])
        fill_rect(img, 10, 12, 12, 11, JP[1])
        fill_rect(img, 10, 12, 12, 3, JP[0])
        fill_rect(img, 10, 20, 12, 3, JP[2])
        fill_rect(img, 10, 21, 12, 2, PB[2])
        # Hair
        fill_rect(img, 10, 4, 12, 9, HW[1])
        fill_rect(img, 10, 4, 12, 2, HW[0])
        px(img, 9, 5, HW[0])
        px(img, 14, 2, HW[0])
        # Face
        fill_rect(img, 10, 9, 6, 4, SKIN)
        fill_rect(img, 10, 11, 6, 2, SKIN_SHADOW)
        draw_eyes(img, 12, 10, "left")
        # Guitar held left
        fill_rect(img, 6, 10, 2, 10, GG[2])
        fill_rect(img, 4, 17, 5, 5, GR[1])
        fill_rect(img, 5, 18, 3, 3, GR[0])

    elif direction == "right":
        fill_rect(img, 12, 22, 4, 6, PB[1])
        fill_rect(img, 16, 22, 4, 6, PB[1])
        fill_rect(img, 12, 26, 4, 2, PB[2])
        fill_rect(img, 16, 26, 4, 2, PB[2])
        fill_rect(img, 10, 12, 12, 11, JP[1])
        fill_rect(img, 10, 12, 12, 3, JP[0])
        fill_rect(img, 10, 20, 12, 3, JP[2])
        fill_rect(img, 10, 21, 12, 2, PB[2])
        # Hair
        fill_rect(img, 10, 4, 12, 9, HW[1])
        fill_rect(img, 10, 4, 12, 2, HW[0])
        px(img, 22, 5, HW[0])
        px(img, 18, 2, HW[0])
        # Face
        fill_rect(img, 16, 9, 6, 4, SKIN)
        fill_rect(img, 16, 11, 6, 2, SKIN_SHADOW)
        draw_eyes(img, 19, 10, "right")
        # Guitar held right
        fill_rect(img, 24, 10, 2, 10, GG[2])
        fill_rect(img, 23, 17, 5, 5, GR[1])
        fill_rect(img, 24, 18, 3, 3, GR[0])


def make_side_sheet(draw_frame_func, frame_count=6, frame_size=32):
    sheet = Image.new("RGBA", (frame_count * frame_size, frame_size), TRANSP)
    for i in range(frame_count):
        frame = Image.new("RGBA", (frame_size, frame_size), TRANSP)
        draw_frame_func(frame, i)
        frame = apply_outline(frame)
        sheet.paste(frame, (i * frame_size, 0))
    return sheet

def make_topdown_sheet(draw_frame_func):
    sheet = Image.new("RGBA", (128, 128), TRANSP)
    directions = ["down", "left", "right", "up"]
    for row, direction in enumerate(directions):
        for col in range(4):
            frame = Image.new("RGBA", (32, 32), TRANSP)
            walk_phase = col
            draw_frame_func(frame, direction, walk_phase)
            frame = apply_outline(frame)
            sheet.paste(frame, (col * 32, row * 32))
    return sheet


def main():
    print("Generating guitarist sprites...")

    print("  guitarist_side.png")
    sheet = make_side_sheet(draw_guitarist_side, 6, 32)
    sheet.save(os.path.join(OUT, "guitarist_side.png"))
    w, h = sheet.size
    print(f"    Size: {w}x{h}")

    print("  guitarist_topdown.png")
    sheet = make_topdown_sheet(draw_guitarist_topdown)
    sheet.save(os.path.join(OUT, "guitarist_topdown.png"))
    w, h = sheet.size
    print(f"    Size: {w}x{h}")

    print("Done!")


if __name__ == "__main__":
    main()
