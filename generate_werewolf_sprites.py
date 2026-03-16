#!/usr/bin/env python3
"""Generate werewolf character sprites."""

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
TRANSP = (0, 0, 0, 0)

# Werewolf colors - dark brown/gray fur, beast
FUR_DARK = (80, 55, 40)
FUR_MID = (110, 75, 55)
FUR_LIGHT = (140, 100, 70)
FUR_BELLY = (160, 130, 100)
CLAW_WHITE = (220, 215, 200)
FANG_WHITE = (235, 230, 220)
EYE_YELLOW = (255, 200, 50)
EYE_RED = (200, 40, 30)
NOSE_DARK = (50, 35, 30)
INNER_EAR = (150, 90, 70)

FD = pal(FUR_DARK)
FM = pal(FUR_MID)
FL = pal(FUR_LIGHT)

def px(img, x, y, color):
    if 0 <= x < img.width and 0 <= y < img.height:
        if len(color) == 3:
            color = color + (255,)
        img.putpixel((x, y), color)

def fill_rect(img, x0, y0, w, h, color):
    for yy in range(y0, y0 + h):
        for xx in range(x0, x0 + w):
            px(img, xx, yy, color)

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
# Hunched beast with claws, fangs, furry, dark brown/gray
# ---------------------------------------------------------------------------

def draw_werewolf_side(img, frame_idx):
    y_off = -3 if frame_idx == 3 else 0

    # Hunched posture - body leans forward
    # Legs - digitigrade (beast legs)
    if frame_idx == 1:
        fill_rect(img, 10, 24 + y_off, 3, 5, FUR_DARK)
        fill_rect(img, 18, 23 + y_off, 3, 5, FUR_DARK)
    elif frame_idx == 2:
        fill_rect(img, 13, 23 + y_off, 3, 5, FUR_DARK)
        fill_rect(img, 16, 24 + y_off, 3, 5, FUR_DARK)
    else:
        fill_rect(img, 11, 24 + y_off, 3, 5, FUR_DARK)
        fill_rect(img, 17, 24 + y_off, 3, 5, FUR_DARK)

    # Paw feet with claws
    fill_rect(img, 10, 28 + y_off, 4, 2, FUR_MID)
    fill_rect(img, 17, 28 + y_off, 4, 2, FUR_MID)
    px(img, 9, 29 + y_off, CLAW_WHITE)
    px(img, 21, 29 + y_off, CLAW_WHITE)

    # Body - hunched, muscular
    fill_rect(img, 9, 14 + y_off, 14, 10, FUR_MID)
    fill_rect(img, 9, 14 + y_off, 14, 3, FUR_DARK)  # upper back darker
    fill_rect(img, 11, 18 + y_off, 8, 5, FUR_BELLY)  # belly lighter
    # Fur tufts on back/shoulders
    px(img, 8, 14 + y_off, FUR_DARK)
    px(img, 23, 14 + y_off, FUR_DARK)
    px(img, 8, 15 + y_off, FUR_MID)
    px(img, 23, 15 + y_off, FUR_MID)

    # Head - wolf/beast snout
    fill_rect(img, 8, 6 + y_off, 10, 8, FUR_MID)
    fill_rect(img, 8, 6 + y_off, 10, 3, FUR_DARK)  # top of head darker
    # Snout extending forward
    fill_rect(img, 5, 10 + y_off, 5, 4, FUR_LIGHT)
    px(img, 4, 12 + y_off, NOSE_DARK)  # nose
    px(img, 4, 11 + y_off, NOSE_DARK)
    # Fangs
    px(img, 5, 13 + y_off, FANG_WHITE)
    px(img, 7, 13 + y_off, FANG_WHITE)
    # Eyes - yellow, menacing
    px(img, 9, 8 + y_off, EYE_YELLOW)
    px(img, 10, 8 + y_off, EYE_YELLOW)
    px(img, 11, 8 + y_off, EYE_RED)  # inner eye red glow

    # Pointed ears
    px(img, 9, 4 + y_off, FUR_DARK)
    px(img, 10, 3 + y_off, FUR_DARK)
    px(img, 10, 4 + y_off, INNER_EAR)
    px(img, 15, 4 + y_off, FUR_DARK)
    px(img, 16, 3 + y_off, FUR_DARK)
    px(img, 16, 4 + y_off, INNER_EAR)

    # Tail
    fill_rect(img, 22, 16 + y_off, 2, 3, FUR_DARK)
    fill_rect(img, 23, 14 + y_off, 2, 3, FUR_MID)
    px(img, 24, 13 + y_off, FUR_LIGHT)

    # Arms/claws
    if frame_idx in (4, 5):
        # Attack - claws extended forward
        fill_rect(img, 3, 14 + y_off, 6, 3, FUR_MID)
        # Claws
        px(img, 2, 14 + y_off, CLAW_WHITE)
        px(img, 2, 15 + y_off, CLAW_WHITE)
        px(img, 2, 16 + y_off, CLAW_WHITE)
        if frame_idx == 5:
            # Second attack - claws slashing down
            fill_rect(img, 4, 12 + y_off, 5, 3, FUR_MID)
            px(img, 3, 12 + y_off, CLAW_WHITE)
            px(img, 3, 13 + y_off, CLAW_WHITE)
            px(img, 3, 14 + y_off, CLAW_WHITE)
    else:
        # Idle/walk - arms at side, slightly forward (hunched)
        fill_rect(img, 7, 16 + y_off, 3, 6, FUR_MID)
        px(img, 7, 22 + y_off, CLAW_WHITE)
        px(img, 8, 22 + y_off, CLAW_WHITE)


# ---------------------------------------------------------------------------
# Top-down sprite (128x128, 4x4 grid of 32x32)
# Rows: down, left, right, up.  Cols: idle, walk1, walk2, walk3
# ---------------------------------------------------------------------------

def draw_werewolf_topdown(img, direction, phase):
    cx, cy = 15, 15
    leg_offset = [-1, 0, 1, 0][phase]

    if direction == "down":
        # Legs
        fill_rect(img, 10, 22, 4, 6, FUR_DARK)
        fill_rect(img, 18, 22, 4, 6, FUR_DARK)
        if phase in (1, 3):
            fill_rect(img, 10, 22 + leg_offset, 4, 6, FUR_DARK)
        # Paws
        fill_rect(img, 10, 26, 4, 3, FUR_MID)
        fill_rect(img, 18, 26, 4, 3, FUR_MID)
        px(img, 9, 28, CLAW_WHITE)
        px(img, 14, 28, CLAW_WHITE)
        px(img, 17, 28, CLAW_WHITE)
        px(img, 22, 28, CLAW_WHITE)
        # Body - broad shoulders
        fill_rect(img, 8, 12, 16, 11, FUR_MID)
        fill_rect(img, 8, 12, 16, 3, FUR_DARK)
        fill_rect(img, 11, 17, 10, 5, FUR_BELLY)
        # Head - wolf
        fill_rect(img, 10, 4, 12, 9, FUR_MID)
        fill_rect(img, 10, 4, 12, 3, FUR_DARK)
        # Snout
        fill_rect(img, 13, 11, 6, 3, FUR_LIGHT)
        px(img, 15, 13, NOSE_DARK)
        px(img, 16, 13, NOSE_DARK)
        # Fangs
        px(img, 13, 13, FANG_WHITE)
        px(img, 18, 13, FANG_WHITE)
        # Eyes
        px(img, 12, 7, EYE_YELLOW)
        px(img, 13, 7, EYE_YELLOW)
        px(img, 18, 7, EYE_YELLOW)
        px(img, 19, 7, EYE_YELLOW)
        # Ears
        px(img, 10, 3, FUR_DARK)
        px(img, 11, 2, FUR_DARK)
        px(img, 11, 3, INNER_EAR)
        px(img, 20, 3, FUR_DARK)
        px(img, 21, 2, FUR_DARK)
        px(img, 21, 3, INNER_EAR)

    elif direction == "up":
        fill_rect(img, 10, 22, 4, 6, FUR_DARK)
        fill_rect(img, 18, 22, 4, 6, FUR_DARK)
        fill_rect(img, 10, 26, 4, 3, FUR_MID)
        fill_rect(img, 18, 26, 4, 3, FUR_MID)
        fill_rect(img, 8, 12, 16, 11, FUR_MID)
        fill_rect(img, 8, 12, 16, 3, FUR_DARK)
        # Head from behind
        fill_rect(img, 10, 4, 12, 9, FUR_MID)
        fill_rect(img, 10, 4, 12, 3, FUR_DARK)
        fill_rect(img, 10, 10, 12, 3, FUR_DARK)
        # Ears from behind
        px(img, 10, 3, FUR_DARK)
        px(img, 11, 2, FUR_DARK)
        px(img, 20, 3, FUR_DARK)
        px(img, 21, 2, FUR_DARK)
        # Tail
        fill_rect(img, 14, 22, 4, 3, FUR_DARK)
        px(img, 15, 25, FUR_LIGHT)

    elif direction == "left":
        fill_rect(img, 12, 22, 4, 6, FUR_DARK)
        fill_rect(img, 16, 22, 4, 6, FUR_DARK)
        fill_rect(img, 12, 26, 4, 3, FUR_MID)
        fill_rect(img, 16, 26, 4, 3, FUR_MID)
        fill_rect(img, 8, 12, 16, 11, FUR_MID)
        fill_rect(img, 8, 12, 16, 3, FUR_DARK)
        # Head - side view with snout
        fill_rect(img, 10, 4, 10, 9, FUR_MID)
        fill_rect(img, 10, 4, 10, 3, FUR_DARK)
        fill_rect(img, 6, 8, 5, 4, FUR_LIGHT)  # snout
        px(img, 5, 10, NOSE_DARK)
        px(img, 6, 11, FANG_WHITE)
        px(img, 8, 11, FANG_WHITE)
        # Eye
        px(img, 11, 7, EYE_YELLOW)
        px(img, 12, 7, EYE_YELLOW)
        # Ear
        px(img, 12, 3, FUR_DARK)
        px(img, 13, 2, FUR_DARK)
        px(img, 13, 3, INNER_EAR)
        # Claws on left arm
        px(img, 7, 22, CLAW_WHITE)
        px(img, 8, 22, CLAW_WHITE)

    elif direction == "right":
        fill_rect(img, 12, 22, 4, 6, FUR_DARK)
        fill_rect(img, 16, 22, 4, 6, FUR_DARK)
        fill_rect(img, 12, 26, 4, 3, FUR_MID)
        fill_rect(img, 16, 26, 4, 3, FUR_MID)
        fill_rect(img, 8, 12, 16, 11, FUR_MID)
        fill_rect(img, 8, 12, 16, 3, FUR_DARK)
        # Head - side view with snout
        fill_rect(img, 12, 4, 10, 9, FUR_MID)
        fill_rect(img, 12, 4, 10, 3, FUR_DARK)
        fill_rect(img, 21, 8, 5, 4, FUR_LIGHT)  # snout
        px(img, 26, 10, NOSE_DARK)
        px(img, 24, 11, FANG_WHITE)
        px(img, 22, 11, FANG_WHITE)
        # Eye
        px(img, 19, 7, EYE_YELLOW)
        px(img, 20, 7, EYE_YELLOW)
        # Ear
        px(img, 19, 3, FUR_DARK)
        px(img, 18, 2, FUR_DARK)
        px(img, 18, 3, INNER_EAR)
        # Claws on right arm
        px(img, 23, 22, CLAW_WHITE)
        px(img, 24, 22, CLAW_WHITE)


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
    print("Generating werewolf sprites...")

    print("  werewolf_side.png")
    sheet = make_side_sheet(draw_werewolf_side, 6, 32)
    sheet.save(os.path.join(OUT, "werewolf_side.png"))
    w, h = sheet.size
    print(f"    Size: {w}x{h}")

    print("  werewolf_topdown.png")
    sheet = make_topdown_sheet(draw_werewolf_topdown)
    sheet.save(os.path.join(OUT, "werewolf_topdown.png"))
    w, h = sheet.size
    print(f"    Size: {w}x{h}")

    print("Done!")


if __name__ == "__main__":
    main()
