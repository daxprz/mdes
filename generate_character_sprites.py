#!/usr/bin/env python3
"""Generate ALL character sprite sheets for the Godot 4 game.

Each sprite is drawn pixel-by-pixel with:
- 1px dark outline
- 3-4 shading tones per color area
- Readable silhouette at small size
- Visible facial features
"""

from PIL import Image, ImageDraw
import os

OUT = "/Users/jeremy/dev/dax/test123/assets/sprites/characters"
os.makedirs(OUT, exist_ok=True)

# ---------------------------------------------------------------------------
# Color palette helpers
# ---------------------------------------------------------------------------

def shade(base, factor):
    """Darken or lighten a color. factor<1 darkens, >1 lightens."""
    return tuple(max(0, min(255, int(c * factor))) for c in base)

def blend(c1, c2, t=0.5):
    return tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))

# Standard palette builder: returns (highlight, base, shadow, deep_shadow)
def pal(base_color):
    return (
        shade(base_color, 1.35),
        base_color,
        shade(base_color, 0.65),
        shade(base_color, 0.40),
    )

# Common colors
BLACK = (20, 20, 25)
OUTLINE = (15, 15, 20)
SKIN = (235, 195, 155)
SKIN_SHADOW = (200, 160, 120)
SKIN_DEEP = (170, 130, 95)
WHITE_EYE = (255, 255, 255)
PUPIL = (30, 30, 40)
TRANSP = (0, 0, 0, 0)

# ---------------------------------------------------------------------------
# Drawing primitives
# ---------------------------------------------------------------------------

def px(img, x, y, color):
    """Set a pixel if within bounds, handling alpha."""
    if 0 <= x < img.width and 0 <= y < img.height:
        if len(color) == 3:
            color = color + (255,)
        img.putpixel((x, y), color)

def fill_rect(img, x0, y0, w, h, color):
    for yy in range(y0, y0 + h):
        for xx in range(x0, x0 + w):
            px(img, xx, yy, color)

def outline_rect(img, x0, y0, w, h, color=OUTLINE):
    for xx in range(x0, x0 + w):
        px(img, xx, y0, color)
        px(img, xx, y0 + h - 1, color)
    for yy in range(y0, y0 + h):
        px(img, x0, yy, color)
        px(img, x0 + w - 1, yy, color)

def draw_eyes(img, cx, cy, direction="down", glow_color=None):
    """Draw a pair of eyes. cx,cy is center of face."""
    eye_color = glow_color if glow_color else PUPIL
    if direction == "down":
        px(img, cx - 2, cy, WHITE_EYE)
        px(img, cx - 1, cy, eye_color)
        px(img, cx + 1, cy, WHITE_EYE)
        px(img, cx + 2, cy, eye_color)
    elif direction == "up":
        # Eyes not visible from behind - just show helmet/hood back
        pass
    elif direction == "left":
        px(img, cx - 1, cy, WHITE_EYE)
        px(img, cx, cy, eye_color)
    elif direction == "right":
        px(img, cx, cy, WHITE_EYE)
        px(img, cx + 1, cy, eye_color)

def apply_outline(img):
    """Add a 1px dark outline around all non-transparent pixels."""
    w, h = img.size
    outline_img = Image.new("RGBA", (w, h), TRANSP)
    pixels = img.load()
    out_px = outline_img.load()
    # First pass: mark outline pixels
    for y in range(h):
        for x in range(w):
            if pixels[x, y][3] > 0:
                continue
            # Check neighbors
            for dx, dy in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and pixels[nx, ny][3] > 0:
                    out_px[x, y] = OUTLINE + (255,)
                    break
    # Composite: outline behind original
    result = Image.new("RGBA", (w, h), TRANSP)
    result.paste(outline_img, (0, 0))
    result.paste(img, (0, 0), img)
    return result


# ---------------------------------------------------------------------------
# Topdown sprite helpers
# ---------------------------------------------------------------------------

def make_topdown_sheet(draw_frame_func):
    """Create a 128x128 sheet: 4 cols x 4 rows of 32x32 frames.
    Rows: down, left, right, up.  Cols: idle, walk1, walk2, walk3 (cycle)."""
    sheet = Image.new("RGBA", (128, 128), TRANSP)
    directions = ["down", "left", "right", "up"]
    for row, direction in enumerate(directions):
        for col in range(4):
            frame = Image.new("RGBA", (32, 32), TRANSP)
            walk_phase = col  # 0=idle, 1-3=walk cycle
            draw_frame_func(frame, direction, walk_phase)
            frame = apply_outline(frame)
            sheet.paste(frame, (col * 32, row * 32))
    return sheet

def make_side_sheet(draw_frame_func, frame_count=6, frame_size=32):
    """Create a horizontal strip of side-view frames."""
    sheet = Image.new("RGBA", (frame_count * frame_size, frame_size), TRANSP)
    for i in range(frame_count):
        frame = Image.new("RGBA", (frame_size, frame_size), TRANSP)
        draw_frame_func(frame, i)
        frame = apply_outline(frame)
        sheet.paste(frame, (i * frame_size, 0))
    return sheet


# ===================================================================
# 1. MELEE KNIGHT - Blue/Silver
# ===================================================================

KNIGHT_BLUE = (60, 90, 170)
KNIGHT_SILVER = (180, 185, 195)

KB = pal(KNIGHT_BLUE)
KS = pal(KNIGHT_SILVER)

def draw_knight_topdown(img, direction, phase):
    cx, cy = 15, 15  # center
    leg_offset = [-1, 0, 1, 0][phase]

    if direction == "down":
        # Legs
        fill_rect(img, 11, 22, 4, 6, KB[1])
        fill_rect(img, 17, 22, 4, 6, KB[1])
        fill_rect(img, 11, 26, 4, 2, KB[2])
        fill_rect(img, 17, 26, 4, 2, KB[2])
        if phase in (1, 3):
            fill_rect(img, 11, 22 + leg_offset, 4, 6, KB[1])
        # Body armor
        fill_rect(img, 10, 12, 12, 11, KB[1])
        fill_rect(img, 10, 12, 12, 3, KB[0])  # highlight top
        fill_rect(img, 10, 20, 12, 3, KB[2])  # shadow bottom
        # Silver chest plate
        fill_rect(img, 12, 14, 8, 6, KS[1])
        fill_rect(img, 12, 14, 8, 2, KS[0])
        fill_rect(img, 12, 18, 8, 2, KS[2])
        # Pauldrons (shoulder armor)
        fill_rect(img, 7, 12, 4, 5, KS[1])
        fill_rect(img, 7, 12, 4, 2, KS[0])
        fill_rect(img, 7, 15, 4, 2, KS[2])
        fill_rect(img, 21, 12, 4, 5, KS[1])
        fill_rect(img, 21, 12, 4, 2, KS[0])
        fill_rect(img, 21, 15, 4, 2, KS[2])
        # Helmet
        fill_rect(img, 11, 5, 10, 8, KS[1])
        fill_rect(img, 11, 5, 10, 3, KS[0])
        fill_rect(img, 11, 10, 10, 3, KS[2])
        # Visor slit
        fill_rect(img, 13, 9, 6, 2, BLACK)
        px(img, 14, 9, (100, 150, 255))  # eye glow left
        px(img, 17, 9, (100, 150, 255))  # eye glow right
        # Greatsword (right side)
        fill_rect(img, 25, 4, 2, 20, KS[1])
        fill_rect(img, 25, 4, 2, 2, KS[0])
        fill_rect(img, 24, 12, 4, 2, KB[2])  # crossguard
        px(img, 25, 3, KS[0])  # sword tip

    elif direction == "up":
        # Legs
        fill_rect(img, 11, 22, 4, 6, KB[1])
        fill_rect(img, 17, 22, 4, 6, KB[1])
        fill_rect(img, 11, 26, 4, 2, KB[2])
        fill_rect(img, 17, 26, 4, 2, KB[2])
        # Body
        fill_rect(img, 10, 12, 12, 11, KB[1])
        fill_rect(img, 10, 12, 12, 3, KB[0])
        fill_rect(img, 10, 20, 12, 3, KB[2])
        # Back of armor
        fill_rect(img, 12, 14, 8, 6, KB[2])
        # Pauldrons
        fill_rect(img, 7, 12, 4, 5, KS[1])
        fill_rect(img, 21, 12, 4, 5, KS[1])
        # Helmet back
        fill_rect(img, 11, 5, 10, 8, KS[1])
        fill_rect(img, 11, 5, 10, 3, KS[0])
        fill_rect(img, 13, 11, 6, 2, KS[2])
        # Sword on back
        fill_rect(img, 15, 2, 2, 22, KS[1])
        fill_rect(img, 14, 12, 4, 2, KB[2])

    elif direction == "left":
        # Legs
        fill_rect(img, 12, 22, 4, 6, KB[1])
        fill_rect(img, 16, 22, 4, 6, KB[2])
        # Body
        fill_rect(img, 11, 12, 10, 11, KB[1])
        fill_rect(img, 11, 12, 4, 11, KB[0])
        fill_rect(img, 17, 12, 4, 11, KB[2])
        # Pauldron
        fill_rect(img, 8, 12, 4, 5, KS[1])
        fill_rect(img, 8, 12, 4, 2, KS[0])
        # Helmet
        fill_rect(img, 10, 5, 10, 8, KS[1])
        fill_rect(img, 10, 5, 4, 8, KS[0])
        # Visor
        fill_rect(img, 10, 9, 4, 2, BLACK)
        px(img, 11, 9, (100, 150, 255))
        # Sword
        fill_rect(img, 7, 5, 2, 18, KS[1])
        fill_rect(img, 6, 12, 4, 2, KB[2])

    elif direction == "right":
        fill_rect(img, 12, 22, 4, 6, KB[2])
        fill_rect(img, 16, 22, 4, 6, KB[1])
        fill_rect(img, 11, 12, 10, 11, KB[1])
        fill_rect(img, 11, 12, 4, 11, KB[2])
        fill_rect(img, 17, 12, 4, 11, KB[0])
        fill_rect(img, 20, 12, 4, 5, KS[1])
        fill_rect(img, 20, 12, 4, 2, KS[0])
        fill_rect(img, 12, 5, 10, 8, KS[1])
        fill_rect(img, 18, 5, 4, 8, KS[0])
        fill_rect(img, 18, 9, 4, 2, BLACK)
        px(img, 20, 9, (100, 150, 255))
        fill_rect(img, 23, 5, 2, 18, KS[1])
        fill_rect(img, 22, 12, 4, 2, KB[2])


def draw_knight_side(img, frame_idx):
    """0=idle, 1=walk1, 2=walk2, 3=jump, 4=attack1, 5=attack2"""
    y_off = 0
    if frame_idx == 3:
        y_off = -3  # jump

    # Legs
    if frame_idx == 0:  # idle
        fill_rect(img, 11, 24 + y_off, 4, 6, KB[1])
        fill_rect(img, 17, 24 + y_off, 4, 6, KB[1])
    elif frame_idx == 1:  # walk1
        fill_rect(img, 9, 24, 4, 6, KB[1])
        fill_rect(img, 19, 23, 4, 6, KB[1])
    elif frame_idx == 2:  # walk2
        fill_rect(img, 13, 23, 4, 6, KB[1])
        fill_rect(img, 15, 24, 4, 6, KB[1])
    elif frame_idx == 3:  # jump
        fill_rect(img, 11, 22 + y_off, 4, 5, KB[1])
        fill_rect(img, 17, 23 + y_off, 4, 5, KB[1])
    elif frame_idx == 4:  # attack1 - wind up
        fill_rect(img, 11, 24, 4, 6, KB[1])
        fill_rect(img, 17, 24, 4, 6, KB[1])
    elif frame_idx == 5:  # attack2 - swing
        fill_rect(img, 10, 24, 4, 6, KB[1])
        fill_rect(img, 16, 24, 4, 6, KB[1])

    # Feet darker
    fill_rect(img, 11, 28 + y_off, 4, 2, KB[2])
    fill_rect(img, 17, 28 + y_off, 4, 2, KB[2])

    # Body
    fill_rect(img, 10, 14 + y_off, 12, 10, KB[1])
    fill_rect(img, 10, 14 + y_off, 12, 3, KB[0])
    fill_rect(img, 10, 21 + y_off, 12, 3, KB[2])
    # Chest plate
    fill_rect(img, 12, 16 + y_off, 8, 5, KS[1])
    fill_rect(img, 12, 16 + y_off, 8, 2, KS[0])
    # Pauldron
    fill_rect(img, 8, 13 + y_off, 4, 4, KS[1])
    fill_rect(img, 8, 13 + y_off, 4, 2, KS[0])
    fill_rect(img, 20, 13 + y_off, 4, 4, KS[1])

    # Helmet
    fill_rect(img, 11, 5 + y_off, 10, 9, KS[1])
    fill_rect(img, 11, 5 + y_off, 10, 3, KS[0])
    fill_rect(img, 11, 11 + y_off, 10, 3, KS[2])
    # Visor
    fill_rect(img, 11, 9 + y_off, 5, 2, BLACK)
    px(img, 12, 9 + y_off, (100, 150, 255))

    # Sword
    if frame_idx == 4:  # attack wind-up: sword raised
        fill_rect(img, 22, 2 + y_off, 2, 14, KS[1])
        fill_rect(img, 21, 12 + y_off, 4, 2, KB[2])
        px(img, 22, 1 + y_off, KS[0])
    elif frame_idx == 5:  # attack swing: sword forward
        fill_rect(img, 15, 10 + y_off, 16, 2, KS[1])
        fill_rect(img, 20, 9 + y_off, 2, 4, KB[2])
        px(img, 30, 10 + y_off, KS[0])
    else:
        # Sword at side
        fill_rect(img, 23, 6 + y_off, 2, 18, KS[1])
        fill_rect(img, 22, 14 + y_off, 4, 2, KB[2])
        px(img, 23, 5 + y_off, KS[0])


# ===================================================================
# 2. RANGED RANGER - Green/Brown
# ===================================================================

RANGER_GREEN = (55, 120, 55)
RANGER_BROWN = (120, 80, 45)

RG = pal(RANGER_GREEN)
RB = pal(RANGER_BROWN)

def draw_ranger_topdown(img, direction, phase):
    leg_off = [-1, 0, 1, 0][phase]

    if direction == "down":
        # Legs
        fill_rect(img, 12, 22, 3, 7, RB[1])
        fill_rect(img, 17, 22, 3, 7, RB[1])
        fill_rect(img, 12, 27, 3, 2, RB[2])
        fill_rect(img, 17, 27, 3, 2, RB[2])
        # Body - leather armor
        fill_rect(img, 11, 13, 10, 10, RG[1])
        fill_rect(img, 11, 13, 10, 3, RG[0])
        fill_rect(img, 11, 20, 10, 3, RG[2])
        # Belt
        fill_rect(img, 11, 21, 10, 2, RB[1])
        # Quiver on back (peeks over shoulder)
        fill_rect(img, 21, 8, 3, 10, RB[1])
        fill_rect(img, 21, 8, 3, 2, RB[0])
        px(img, 22, 7, (200, 180, 100))  # arrow tips
        px(img, 21, 7, (200, 180, 100))
        # Hood
        fill_rect(img, 10, 5, 12, 9, RG[2])
        fill_rect(img, 10, 5, 12, 3, RG[1])
        # Face visible under hood
        fill_rect(img, 12, 8, 8, 5, SKIN)
        fill_rect(img, 12, 11, 8, 2, SKIN_SHADOW)
        # Eyes
        draw_eyes(img, 16, 9, "down")
        # Crossbow in hand
        fill_rect(img, 6, 16, 5, 2, RB[2])
        fill_rect(img, 7, 14, 2, 6, RB[1])
        px(img, 6, 15, (160, 160, 170))  # bolt

    elif direction == "up":
        fill_rect(img, 12, 22, 3, 7, RB[1])
        fill_rect(img, 17, 22, 3, 7, RB[1])
        fill_rect(img, 11, 13, 10, 10, RG[1])
        fill_rect(img, 11, 13, 10, 3, RG[0])
        fill_rect(img, 11, 20, 10, 3, RG[2])
        fill_rect(img, 11, 21, 10, 2, RB[1])
        # Quiver clearly visible
        fill_rect(img, 14, 6, 4, 12, RB[1])
        fill_rect(img, 14, 6, 4, 2, RB[0])
        px(img, 15, 5, (200, 180, 100))
        px(img, 16, 5, (200, 180, 100))
        px(img, 17, 5, (200, 180, 100))
        # Hood back
        fill_rect(img, 10, 5, 12, 9, RG[2])
        fill_rect(img, 10, 5, 12, 3, RG[1])

    elif direction == "left":
        fill_rect(img, 13, 22, 3, 7, RB[1])
        fill_rect(img, 16, 22, 3, 7, RB[2])
        fill_rect(img, 11, 13, 9, 10, RG[1])
        fill_rect(img, 11, 13, 3, 10, RG[0])
        fill_rect(img, 17, 13, 3, 10, RG[2])
        # Hood
        fill_rect(img, 10, 5, 10, 9, RG[2])
        fill_rect(img, 10, 5, 4, 9, RG[1])
        # Face
        fill_rect(img, 10, 8, 5, 4, SKIN)
        fill_rect(img, 10, 10, 5, 2, SKIN_SHADOW)
        draw_eyes(img, 12, 9, "left")
        # Crossbow
        fill_rect(img, 7, 15, 4, 2, RB[2])
        fill_rect(img, 8, 13, 2, 6, RB[1])
        # Quiver
        fill_rect(img, 19, 7, 3, 9, RB[1])

    elif direction == "right":
        fill_rect(img, 13, 22, 3, 7, RB[2])
        fill_rect(img, 16, 22, 3, 7, RB[1])
        fill_rect(img, 12, 13, 9, 10, RG[1])
        fill_rect(img, 12, 13, 3, 10, RG[2])
        fill_rect(img, 18, 13, 3, 10, RG[0])
        fill_rect(img, 12, 5, 10, 9, RG[2])
        fill_rect(img, 18, 5, 4, 9, RG[1])
        fill_rect(img, 17, 8, 5, 4, SKIN)
        fill_rect(img, 17, 10, 5, 2, SKIN_SHADOW)
        draw_eyes(img, 19, 9, "right")
        fill_rect(img, 21, 15, 4, 2, RB[2])
        fill_rect(img, 22, 13, 2, 6, RB[1])
        fill_rect(img, 10, 7, 3, 9, RB[1])


def draw_ranger_side(img, frame_idx):
    y_off = -3 if frame_idx == 3 else 0

    # Legs
    if frame_idx == 1:
        fill_rect(img, 10, 24, 3, 6, RB[1])
        fill_rect(img, 19, 23, 3, 6, RB[1])
    elif frame_idx == 2:
        fill_rect(img, 14, 23, 3, 6, RB[1])
        fill_rect(img, 15, 24, 3, 6, RB[1])
    else:
        fill_rect(img, 12, 24 + y_off, 3, 6, RB[1])
        fill_rect(img, 17, 24 + y_off, 3, 6, RB[1])

    # Body
    fill_rect(img, 11, 14 + y_off, 10, 10, RG[1])
    fill_rect(img, 11, 14 + y_off, 10, 3, RG[0])
    fill_rect(img, 11, 21 + y_off, 10, 3, RG[2])
    fill_rect(img, 11, 22 + y_off, 10, 2, RB[1])

    # Hood
    fill_rect(img, 10, 5 + y_off, 11, 10, RG[2])
    fill_rect(img, 10, 5 + y_off, 11, 3, RG[1])
    fill_rect(img, 13, 5 + y_off, 3, 2, RG[0])  # hood peak
    # Face
    fill_rect(img, 10, 8 + y_off, 6, 5, SKIN)
    fill_rect(img, 10, 11 + y_off, 6, 2, SKIN_SHADOW)
    draw_eyes(img, 12, 9 + y_off, "left")

    # Quiver
    fill_rect(img, 20, 7 + y_off, 3, 10, RB[1])
    px(img, 21, 6 + y_off, (200, 180, 100))
    px(img, 20, 6 + y_off, (200, 180, 100))

    # Crossbow
    if frame_idx == 4:  # attack1 - aiming
        fill_rect(img, 4, 14 + y_off, 8, 2, RB[2])
        fill_rect(img, 6, 12 + y_off, 2, 6, RB[1])
        px(img, 3, 14 + y_off, (160, 160, 170))
    elif frame_idx == 5:  # attack2 - fired
        fill_rect(img, 4, 14 + y_off, 8, 2, RB[2])
        fill_rect(img, 6, 12 + y_off, 2, 6, RB[1])
        # Bolt flying
        fill_rect(img, 0, 14 + y_off, 3, 1, (160, 160, 170))
    else:
        fill_rect(img, 7, 16 + y_off, 5, 2, RB[2])
        fill_rect(img, 8, 14 + y_off, 2, 6, RB[1])


# ===================================================================
# 3. MAGE WIZARD - Purple/Gold
# ===================================================================

MAGE_PURPLE = (100, 50, 150)
MAGE_GOLD = (200, 170, 50)

MP = pal(MAGE_PURPLE)
MG = pal(MAGE_GOLD)

def draw_mage_topdown(img, direction, phase):
    robe_sway = [-1, 0, 1, 0][phase]

    if direction == "down":
        # Robe bottom (wide, flowing)
        fill_rect(img, 9, 20, 14, 9, MP[1])
        fill_rect(img, 9, 20, 14, 2, MP[0])
        fill_rect(img, 9, 26, 14, 3, MP[2])
        fill_rect(img, 11, 28, 2, 1, MP[3])
        fill_rect(img, 19, 28, 2, 1, MP[3])
        # Gold trim
        fill_rect(img, 9, 27, 14, 1, MG[1])
        # Body/robe upper
        fill_rect(img, 11, 12, 10, 9, MP[1])
        fill_rect(img, 11, 12, 10, 3, MP[0])
        fill_rect(img, 11, 18, 10, 3, MP[2])
        # Gold sash
        fill_rect(img, 15, 14, 2, 6, MG[1])
        px(img, 15, 14, MG[0])
        # Pointed hat
        fill_rect(img, 11, 7, 10, 6, MP[1])
        fill_rect(img, 11, 7, 10, 2, MP[0])
        fill_rect(img, 12, 5, 8, 3, MP[1])
        fill_rect(img, 13, 3, 6, 3, MP[0])
        fill_rect(img, 14, 1, 4, 3, MP[0])
        px(img, 15, 0, MP[0])
        # Stars on hat
        px(img, 13, 5, MG[0])
        px(img, 18, 7, MG[0])
        px(img, 15, 3, MG[0])
        # Hat brim
        fill_rect(img, 9, 10, 14, 2, MP[2])
        # Face (beard)
        fill_rect(img, 12, 10, 8, 4, SKIN)
        fill_rect(img, 13, 13, 6, 3, (200, 200, 210))  # beard
        fill_rect(img, 14, 15, 4, 2, (180, 180, 190))  # beard shadow
        draw_eyes(img, 16, 11, "down")
        # Staff (left side)
        fill_rect(img, 5, 4, 2, 22, RB[1])
        fill_rect(img, 5, 4, 2, 2, RB[0])
        # Orb on staff
        fill_rect(img, 4, 2, 4, 4, (100, 180, 255))
        fill_rect(img, 5, 2, 2, 1, (180, 220, 255))
        fill_rect(img, 4, 5, 4, 1, (60, 120, 200))

    elif direction == "up":
        fill_rect(img, 9, 20, 14, 9, MP[1])
        fill_rect(img, 9, 26, 14, 3, MP[2])
        fill_rect(img, 9, 27, 14, 1, MG[1])
        fill_rect(img, 11, 12, 10, 9, MP[1])
        fill_rect(img, 11, 12, 10, 3, MP[0])
        fill_rect(img, 11, 7, 10, 6, MP[1])
        fill_rect(img, 12, 5, 8, 3, MP[1])
        fill_rect(img, 13, 3, 6, 3, MP[0])
        fill_rect(img, 14, 1, 4, 3, MP[0])
        px(img, 15, 0, MP[0])
        fill_rect(img, 9, 10, 14, 2, MP[2])
        px(img, 13, 5, MG[0])
        px(img, 18, 7, MG[0])
        fill_rect(img, 5, 4, 2, 22, RB[1])
        fill_rect(img, 4, 2, 4, 4, (100, 180, 255))

    elif direction == "left":
        fill_rect(img, 10, 20, 12, 9, MP[1])
        fill_rect(img, 10, 26, 12, 3, MP[2])
        fill_rect(img, 10, 27, 12, 1, MG[1])
        fill_rect(img, 11, 12, 9, 9, MP[1])
        fill_rect(img, 11, 12, 3, 9, MP[0])
        fill_rect(img, 17, 12, 3, 9, MP[2])
        fill_rect(img, 11, 7, 9, 6, MP[1])
        fill_rect(img, 12, 5, 7, 3, MP[1])
        fill_rect(img, 13, 3, 5, 3, MP[0])
        fill_rect(img, 14, 1, 3, 3, MP[0])
        fill_rect(img, 9, 10, 12, 2, MP[2])
        px(img, 14, 4, MG[0])
        fill_rect(img, 11, 10, 5, 4, SKIN)
        fill_rect(img, 11, 13, 4, 2, (200, 200, 210))
        draw_eyes(img, 13, 11, "left")
        fill_rect(img, 7, 4, 2, 22, RB[1])
        fill_rect(img, 6, 2, 4, 4, (100, 180, 255))
        fill_rect(img, 7, 2, 2, 1, (180, 220, 255))

    elif direction == "right":
        fill_rect(img, 10, 20, 12, 9, MP[1])
        fill_rect(img, 10, 26, 12, 3, MP[2])
        fill_rect(img, 10, 27, 12, 1, MG[1])
        fill_rect(img, 12, 12, 9, 9, MP[1])
        fill_rect(img, 12, 12, 3, 9, MP[2])
        fill_rect(img, 18, 12, 3, 9, MP[0])
        fill_rect(img, 12, 7, 9, 6, MP[1])
        fill_rect(img, 13, 5, 7, 3, MP[1])
        fill_rect(img, 14, 3, 5, 3, MP[0])
        fill_rect(img, 15, 1, 3, 3, MP[0])
        fill_rect(img, 11, 10, 12, 2, MP[2])
        px(img, 17, 4, MG[0])
        fill_rect(img, 16, 10, 5, 4, SKIN)
        fill_rect(img, 17, 13, 4, 2, (200, 200, 210))
        draw_eyes(img, 18, 11, "right")
        fill_rect(img, 23, 4, 2, 22, RB[1])
        fill_rect(img, 22, 2, 4, 4, (100, 180, 255))
        fill_rect(img, 23, 2, 2, 1, (180, 220, 255))


def draw_mage_side(img, frame_idx):
    y_off = -3 if frame_idx == 3 else 0

    # Robe bottom
    fill_rect(img, 9, 22 + y_off, 14, 8, MP[1])
    fill_rect(img, 9, 22 + y_off, 14, 2, MP[0])
    fill_rect(img, 9, 27 + y_off, 14, 3, MP[2])
    fill_rect(img, 9, 28 + y_off, 14, 1, MG[1])
    # Walk animation feet
    if frame_idx == 1:
        fill_rect(img, 8, 28 + y_off, 3, 2, MP[2])
        fill_rect(img, 20, 27 + y_off, 3, 2, MP[2])
    elif frame_idx == 2:
        fill_rect(img, 12, 28 + y_off, 3, 2, MP[2])
        fill_rect(img, 16, 28 + y_off, 3, 2, MP[2])

    # Upper robe
    fill_rect(img, 10, 13 + y_off, 12, 10, MP[1])
    fill_rect(img, 10, 13 + y_off, 12, 3, MP[0])
    fill_rect(img, 10, 20 + y_off, 12, 3, MP[2])
    # Gold sash
    fill_rect(img, 15, 15 + y_off, 2, 6, MG[1])

    # Hat
    fill_rect(img, 10, 8 + y_off, 11, 6, MP[1])
    fill_rect(img, 10, 8 + y_off, 11, 2, MP[0])
    fill_rect(img, 11, 6 + y_off, 8, 3, MP[1])
    fill_rect(img, 12, 4 + y_off, 6, 3, MP[0])
    fill_rect(img, 13, 2 + y_off, 4, 3, MP[0])
    px(img, 14, 1 + y_off, MP[0])
    fill_rect(img, 8, 11 + y_off, 14, 2, MP[2])
    px(img, 12, 5 + y_off, MG[0])
    px(img, 17, 8 + y_off, MG[0])

    # Face
    fill_rect(img, 10, 11 + y_off, 6, 5, SKIN)
    fill_rect(img, 10, 14 + y_off, 5, 3, (200, 200, 210))  # beard
    draw_eyes(img, 12, 12 + y_off, "left")

    # Staff
    if frame_idx in (4, 5):
        # Attack - staff forward, orb glowing
        fill_rect(img, 3, 8 + y_off, 8, 2, RB[1])
        fill_rect(img, 1, 6 + y_off, 4, 4, (140, 220, 255))
        fill_rect(img, 2, 6 + y_off, 2, 1, (220, 240, 255))
        if frame_idx == 5:
            # Extra glow
            fill_rect(img, 0, 5 + y_off, 6, 6, (100, 180, 255, 150))
    else:
        fill_rect(img, 5, 3 + y_off, 2, 22, RB[1])
        fill_rect(img, 4, 1 + y_off, 4, 4, (100, 180, 255))
        fill_rect(img, 5, 1 + y_off, 2, 1, (180, 220, 255))
        fill_rect(img, 4, 4 + y_off, 4, 1, (60, 120, 200))


# ===================================================================
# 4. SUMMONER - Orange/Yellow
# ===================================================================

SUMM_ORANGE = (180, 100, 40)
SUMM_YELLOW = (220, 190, 60)

SO = pal(SUMM_ORANGE)
SY = pal(SUMM_YELLOW)

def draw_summoner_topdown(img, direction, phase):
    sway = [-1, 0, 1, 0][phase]

    if direction == "down":
        # Cape
        fill_rect(img, 10, 16, 12, 12, SO[2])
        fill_rect(img, 10, 16, 12, 3, SO[1])
        fill_rect(img, 10, 25, 12, 3, SO[3])
        # Legs peek under cape
        fill_rect(img, 12, 26, 3, 3, SO[3])
        fill_rect(img, 17, 26, 3, 3, SO[3])
        # Body - arcane robes
        fill_rect(img, 11, 12, 10, 10, SO[1])
        fill_rect(img, 11, 12, 10, 3, SO[0])
        fill_rect(img, 11, 19, 10, 3, SO[2])
        # Arcane patterns on robe
        px(img, 13, 15, SY[0])
        px(img, 18, 15, SY[0])
        px(img, 15, 17, SY[0])
        px(img, 16, 17, SY[0])
        px(img, 14, 19, SY[1])
        px(img, 17, 19, SY[1])
        # Yellow trim
        fill_rect(img, 15, 12, 2, 8, SY[1])
        # Head
        fill_rect(img, 12, 5, 8, 8, SO[1])
        fill_rect(img, 12, 5, 8, 3, SO[0])
        fill_rect(img, 12, 10, 8, 3, SO[2])
        # Face
        fill_rect(img, 13, 7, 6, 5, SKIN)
        fill_rect(img, 13, 10, 6, 2, SKIN_SHADOW)
        draw_eyes(img, 16, 8, "down")
        # Donut staff (right side)
        fill_rect(img, 24, 8, 2, 16, RB[1])
        # Donut topper!
        fill_rect(img, 22, 3, 6, 6, SY[1])
        fill_rect(img, 24, 5, 2, 2, SO[1])  # hole
        fill_rect(img, 22, 3, 6, 2, SY[0])
        fill_rect(img, 22, 7, 6, 2, SY[2])

    elif direction == "up":
        # Cape (prominent from behind)
        fill_rect(img, 9, 12, 14, 16, SO[2])
        fill_rect(img, 9, 12, 14, 3, SO[1])
        fill_rect(img, 9, 25, 14, 3, SO[3])
        # Cape pattern
        px(img, 14, 18, SY[0])
        px(img, 18, 18, SY[0])
        px(img, 16, 22, SY[0])
        fill_rect(img, 12, 26, 3, 2, SO[3])
        fill_rect(img, 17, 26, 3, 2, SO[3])
        fill_rect(img, 12, 5, 8, 8, SO[1])
        fill_rect(img, 12, 5, 8, 3, SO[0])
        fill_rect(img, 24, 8, 2, 16, RB[1])
        fill_rect(img, 22, 3, 6, 6, SY[1])
        fill_rect(img, 24, 5, 2, 2, SO[1])

    elif direction == "left":
        # Cape flows behind
        fill_rect(img, 16, 14, 8, 14, SO[2])
        fill_rect(img, 16, 14, 8, 3, SO[1])
        fill_rect(img, 16, 25, 8, 3, SO[3])
        fill_rect(img, 13, 22, 3, 7, SO[2])
        fill_rect(img, 16, 22, 3, 7, SO[3])
        fill_rect(img, 11, 12, 9, 10, SO[1])
        fill_rect(img, 11, 12, 3, 10, SO[0])
        fill_rect(img, 17, 12, 3, 10, SO[2])
        fill_rect(img, 11, 5, 9, 8, SO[1])
        fill_rect(img, 11, 5, 3, 8, SO[0])
        fill_rect(img, 11, 7, 5, 5, SKIN)
        draw_eyes(img, 13, 9, "left")
        fill_rect(img, 7, 8, 2, 16, RB[1])
        fill_rect(img, 5, 3, 6, 6, SY[1])
        fill_rect(img, 7, 5, 2, 2, SO[1])

    elif direction == "right":
        fill_rect(img, 8, 14, 8, 14, SO[2])
        fill_rect(img, 8, 14, 8, 3, SO[1])
        fill_rect(img, 8, 25, 8, 3, SO[3])
        fill_rect(img, 13, 22, 3, 7, SO[3])
        fill_rect(img, 16, 22, 3, 7, SO[2])
        fill_rect(img, 12, 12, 9, 10, SO[1])
        fill_rect(img, 12, 12, 3, 10, SO[2])
        fill_rect(img, 18, 12, 3, 10, SO[0])
        fill_rect(img, 12, 5, 9, 8, SO[1])
        fill_rect(img, 18, 5, 3, 8, SO[0])
        fill_rect(img, 16, 7, 5, 5, SKIN)
        draw_eyes(img, 18, 9, "right")
        fill_rect(img, 23, 8, 2, 16, RB[1])
        fill_rect(img, 21, 3, 6, 6, SY[1])
        fill_rect(img, 23, 5, 2, 2, SO[1])


def draw_summoner_side(img, frame_idx):
    y_off = -3 if frame_idx == 3 else 0

    # Cape
    fill_rect(img, 17, 14 + y_off, 8, 14, SO[2])
    fill_rect(img, 17, 14 + y_off, 8, 3, SO[1])
    fill_rect(img, 17, 25 + y_off, 8, 3, SO[3])
    if frame_idx in (1, 2):
        fill_rect(img, 19, 26 + y_off, 6, 2, SO[3])  # cape sway

    # Legs
    if frame_idx == 1:
        fill_rect(img, 11, 24, 3, 6, SO[2])
        fill_rect(img, 17, 23, 3, 6, SO[2])
    elif frame_idx == 2:
        fill_rect(img, 14, 23, 3, 6, SO[2])
        fill_rect(img, 14, 24, 3, 6, SO[2])
    else:
        fill_rect(img, 12, 24 + y_off, 3, 6, SO[2])
        fill_rect(img, 16, 24 + y_off, 3, 6, SO[2])

    # Body
    fill_rect(img, 10, 13 + y_off, 11, 10, SO[1])
    fill_rect(img, 10, 13 + y_off, 11, 3, SO[0])
    fill_rect(img, 10, 20 + y_off, 11, 3, SO[2])
    # Patterns
    px(img, 13, 16 + y_off, SY[0])
    px(img, 17, 18 + y_off, SY[0])
    # Yellow trim
    fill_rect(img, 15, 13 + y_off, 2, 8, SY[1])

    # Head
    fill_rect(img, 11, 5 + y_off, 9, 9, SO[1])
    fill_rect(img, 11, 5 + y_off, 9, 3, SO[0])
    fill_rect(img, 11, 7 + y_off, 5, 5, SKIN)
    fill_rect(img, 11, 10 + y_off, 5, 2, SKIN_SHADOW)
    draw_eyes(img, 13, 8 + y_off, "left")

    # Donut staff
    if frame_idx in (4, 5):
        fill_rect(img, 3, 10 + y_off, 8, 2, RB[1])
        fill_rect(img, 1, 6 + y_off, 5, 5, SY[1])
        fill_rect(img, 2, 8 + y_off, 3, 1, SO[1])  # hole
        fill_rect(img, 1, 6 + y_off, 5, 2, SY[0])
        if frame_idx == 5:
            # Summoning glow
            fill_rect(img, 0, 5 + y_off, 7, 7, (255, 200, 80, 120))
    else:
        fill_rect(img, 6, 4 + y_off, 2, 20, RB[1])
        fill_rect(img, 4, 0 + y_off, 6, 5, SY[1])
        fill_rect(img, 6, 2 + y_off, 2, 1, SO[1])
        fill_rect(img, 4, 0 + y_off, 6, 2, SY[0])
        fill_rect(img, 4, 3 + y_off, 6, 2, SY[2])


# ===================================================================
# 5. ROGUE - Dark Red/Black
# ===================================================================

ROGUE_RED = (140, 35, 35)
ROGUE_BLACK = (40, 35, 45)

RR = pal(ROGUE_RED)
RK = pal(ROGUE_BLACK)

def draw_rogue_topdown(img, direction, phase):
    sway = [-1, 0, 1, 0][phase]

    if direction == "down":
        # Tattered cape
        fill_rect(img, 10, 18, 12, 10, RK[1])
        fill_rect(img, 10, 18, 12, 2, RK[0])
        fill_rect(img, 10, 25, 12, 3, RK[2])
        # Tattered edges
        px(img, 10, 27, TRANSP)
        px(img, 12, 28, TRANSP)
        px(img, 21, 27, TRANSP)
        px(img, 19, 28, TRANSP)
        px(img, 14, 28, TRANSP)
        # Legs
        fill_rect(img, 12, 24, 3, 5, RK[2])
        fill_rect(img, 17, 24, 3, 5, RK[2])
        # Body
        fill_rect(img, 11, 12, 10, 9, RR[1])
        fill_rect(img, 11, 12, 10, 3, RR[0])
        fill_rect(img, 11, 18, 10, 3, RR[2])
        # Belt with pouches
        fill_rect(img, 11, 19, 10, 2, RK[1])
        px(img, 12, 19, RR[2])
        px(img, 14, 19, RR[2])
        px(img, 17, 19, RR[2])
        px(img, 19, 19, RR[2])
        # Hood
        fill_rect(img, 11, 5, 10, 8, RK[1])
        fill_rect(img, 11, 5, 10, 3, RK[0])
        fill_rect(img, 11, 10, 10, 3, RK[2])
        # Shadowed face - glowing eyes
        fill_rect(img, 13, 8, 6, 4, RK[3])
        px(img, 14, 9, (255, 80, 80))  # glowing red eye
        px(img, 17, 9, (255, 80, 80))
        px(img, 14, 10, (180, 40, 40))  # eye glow under
        px(img, 17, 10, (180, 40, 40))
        # Twin daggers
        fill_rect(img, 6, 14, 1, 8, (180, 180, 190))
        fill_rect(img, 7, 13, 1, 3, RK[1])  # handle
        fill_rect(img, 25, 14, 1, 8, (180, 180, 190))
        fill_rect(img, 24, 13, 1, 3, RK[1])

    elif direction == "up":
        fill_rect(img, 9, 12, 14, 16, RK[1])
        fill_rect(img, 9, 12, 14, 3, RK[0])
        fill_rect(img, 9, 25, 14, 3, RK[2])
        px(img, 9, 27, TRANSP)
        px(img, 11, 28, TRANSP)
        px(img, 22, 27, TRANSP)
        px(img, 20, 28, TRANSP)
        px(img, 15, 28, TRANSP)
        fill_rect(img, 12, 25, 3, 3, RK[2])
        fill_rect(img, 17, 25, 3, 3, RK[2])
        fill_rect(img, 11, 5, 10, 8, RK[1])
        fill_rect(img, 11, 5, 10, 3, RK[0])
        fill_rect(img, 6, 14, 1, 8, (180, 180, 190))
        fill_rect(img, 25, 14, 1, 8, (180, 180, 190))

    elif direction == "left":
        # Cape
        fill_rect(img, 16, 14, 8, 14, RK[1])
        fill_rect(img, 16, 25, 8, 3, RK[2])
        px(img, 23, 27, TRANSP)
        px(img, 21, 28, TRANSP)
        fill_rect(img, 13, 22, 3, 7, RK[2])
        fill_rect(img, 16, 22, 3, 7, RK[2])
        fill_rect(img, 11, 12, 8, 10, RR[1])
        fill_rect(img, 11, 12, 3, 10, RR[0])
        fill_rect(img, 11, 19, 8, 2, RK[1])
        px(img, 12, 19, RR[2])
        px(img, 14, 19, RR[2])
        fill_rect(img, 10, 5, 9, 8, RK[1])
        fill_rect(img, 10, 5, 3, 8, RK[0])
        fill_rect(img, 10, 8, 4, 4, RK[3])
        px(img, 11, 9, (255, 80, 80))
        # Dagger in front
        fill_rect(img, 8, 14, 1, 7, (180, 180, 190))
        fill_rect(img, 8, 13, 1, 2, RK[1])

    elif direction == "right":
        fill_rect(img, 8, 14, 8, 14, RK[1])
        fill_rect(img, 8, 25, 8, 3, RK[2])
        px(img, 8, 27, TRANSP)
        px(img, 10, 28, TRANSP)
        fill_rect(img, 13, 22, 3, 7, RK[2])
        fill_rect(img, 16, 22, 3, 7, RK[2])
        fill_rect(img, 13, 12, 8, 10, RR[1])
        fill_rect(img, 18, 12, 3, 10, RR[0])
        fill_rect(img, 13, 19, 8, 2, RK[1])
        fill_rect(img, 13, 5, 9, 8, RK[1])
        fill_rect(img, 19, 5, 3, 8, RK[0])
        fill_rect(img, 18, 8, 4, 4, RK[3])
        px(img, 20, 9, (255, 80, 80))
        fill_rect(img, 23, 14, 1, 7, (180, 180, 190))
        fill_rect(img, 23, 13, 1, 2, RK[1])


def draw_rogue_side(img, frame_idx):
    y_off = -3 if frame_idx == 3 else 0

    # Tattered cape
    fill_rect(img, 18, 12 + y_off, 7, 16, RK[1])
    fill_rect(img, 18, 12 + y_off, 7, 3, RK[0])
    fill_rect(img, 18, 25 + y_off, 7, 3, RK[2])
    px(img, 24, 27 + y_off, TRANSP)
    px(img, 22, 28 + y_off, TRANSP)
    px(img, 20, 27 + y_off, TRANSP)

    # Legs
    if frame_idx == 1:
        fill_rect(img, 10, 24, 3, 6, RK[2])
        fill_rect(img, 18, 23, 3, 6, RK[2])
    elif frame_idx == 2:
        fill_rect(img, 14, 23, 3, 6, RK[2])
        fill_rect(img, 15, 24, 3, 6, RK[2])
    else:
        fill_rect(img, 12, 24 + y_off, 3, 6, RK[2])
        fill_rect(img, 16, 24 + y_off, 3, 6, RK[2])

    # Body
    fill_rect(img, 10, 13 + y_off, 10, 10, RR[1])
    fill_rect(img, 10, 13 + y_off, 10, 3, RR[0])
    fill_rect(img, 10, 20 + y_off, 10, 3, RR[2])
    # Belt
    fill_rect(img, 10, 21 + y_off, 10, 2, RK[1])
    px(img, 12, 21 + y_off, RR[2])
    px(img, 15, 21 + y_off, RR[2])
    px(img, 18, 21 + y_off, RR[2])

    # Hood
    fill_rect(img, 10, 5 + y_off, 11, 9, RK[1])
    fill_rect(img, 10, 5 + y_off, 11, 3, RK[0])
    fill_rect(img, 10, 11 + y_off, 11, 3, RK[2])
    # Dark face with glowing eyes
    fill_rect(img, 10, 8 + y_off, 5, 4, RK[3])
    px(img, 12, 9 + y_off, (255, 80, 80))
    px(img, 12, 10 + y_off, (180, 40, 40))

    # Daggers
    if frame_idx == 4:  # attack1 - stab forward
        fill_rect(img, 2, 15 + y_off, 9, 1, (200, 200, 210))
        fill_rect(img, 8, 14 + y_off, 2, 3, RK[1])  # handle
    elif frame_idx == 5:  # attack2 - cross slash
        fill_rect(img, 3, 12 + y_off, 8, 1, (200, 200, 210))
        fill_rect(img, 5, 16 + y_off, 8, 1, (200, 200, 210))
        fill_rect(img, 8, 13 + y_off, 2, 2, RK[1])
    else:
        fill_rect(img, 7, 14 + y_off, 1, 6, (200, 200, 210))
        fill_rect(img, 8, 14 + y_off, 1, 6, (200, 200, 210))
        fill_rect(img, 7, 13 + y_off, 2, 2, RK[1])


# ===================================================================
# 6. DEMOLITIONIST - Orange/Dark Gray
# ===================================================================

DEMO_ORANGE = (220, 130, 40)
DEMO_GRAY = (70, 65, 65)

DO = pal(DEMO_ORANGE)
DG = pal(DEMO_GRAY)

def draw_demo_topdown(img, direction, phase):
    if direction == "down":
        # Legs (sturdy boots)
        fill_rect(img, 11, 23, 4, 6, DG[2])
        fill_rect(img, 17, 23, 4, 6, DG[2])
        fill_rect(img, 11, 27, 4, 2, DG[3])
        fill_rect(img, 17, 27, 4, 2, DG[3])
        # Body - heavy apron over clothes
        fill_rect(img, 10, 12, 12, 11, DO[1])
        fill_rect(img, 10, 12, 12, 3, DO[0])
        fill_rect(img, 10, 20, 12, 3, DO[2])
        # Apron
        fill_rect(img, 12, 14, 8, 8, DG[1])
        fill_rect(img, 12, 14, 8, 2, DG[0])
        fill_rect(img, 12, 20, 8, 2, DG[2])
        # Utility belt
        fill_rect(img, 10, 20, 12, 2, DG[1])
        # Mini bombs on belt
        px(img, 11, 20, DO[0])
        px(img, 13, 20, DO[0])
        px(img, 18, 20, DO[0])
        px(img, 20, 20, DO[0])
        # Head with goggles
        fill_rect(img, 11, 5, 10, 8, SKIN)
        fill_rect(img, 11, 10, 10, 3, SKIN_SHADOW)
        # Goggles
        fill_rect(img, 11, 7, 10, 3, DG[1])
        fill_rect(img, 12, 8, 3, 2, (150, 200, 180))  # goggle lens
        fill_rect(img, 17, 8, 3, 2, (150, 200, 180))
        px(img, 13, 8, (200, 240, 220))  # lens highlight
        px(img, 18, 8, (200, 240, 220))
        # Mouth
        px(img, 15, 11, SKIN_DEEP)
        px(img, 16, 11, SKIN_DEEP)
        # Bomb in hand (left)
        fill_rect(img, 5, 14, 5, 5, DG[1])
        fill_rect(img, 5, 14, 5, 2, DG[0])
        fill_rect(img, 5, 17, 5, 2, DG[2])
        px(img, 7, 13, DO[0])  # fuse
        px(img, 7, 12, (255, 200, 50))  # spark
        px(img, 8, 11, (255, 255, 150))

    elif direction == "up":
        fill_rect(img, 11, 23, 4, 6, DG[2])
        fill_rect(img, 17, 23, 4, 6, DG[2])
        fill_rect(img, 10, 12, 12, 11, DO[1])
        fill_rect(img, 10, 12, 12, 3, DO[0])
        fill_rect(img, 10, 20, 12, 2, DG[1])
        px(img, 11, 20, DO[0])
        px(img, 20, 20, DO[0])
        fill_rect(img, 11, 5, 10, 8, DG[1])  # back of head/goggles strap
        fill_rect(img, 11, 5, 10, 3, DG[0])
        fill_rect(img, 5, 14, 5, 5, DG[1])
        px(img, 7, 13, DO[0])

    elif direction == "left":
        fill_rect(img, 13, 23, 3, 6, DG[2])
        fill_rect(img, 16, 23, 3, 6, DG[2])
        fill_rect(img, 11, 12, 9, 11, DO[1])
        fill_rect(img, 11, 12, 3, 11, DO[0])
        fill_rect(img, 12, 14, 5, 7, DG[1])
        fill_rect(img, 11, 20, 9, 2, DG[1])
        px(img, 12, 20, DO[0])
        px(img, 14, 20, DO[0])
        fill_rect(img, 11, 5, 9, 8, SKIN)
        fill_rect(img, 11, 7, 4, 3, DG[1])
        fill_rect(img, 11, 8, 3, 2, (150, 200, 180))
        px(img, 12, 8, (200, 240, 220))
        draw_eyes(img, 13, 8, "left")
        fill_rect(img, 7, 14, 4, 4, DG[1])
        px(img, 8, 13, DO[0])
        px(img, 8, 12, (255, 200, 50))

    elif direction == "right":
        fill_rect(img, 13, 23, 3, 6, DG[2])
        fill_rect(img, 16, 23, 3, 6, DG[2])
        fill_rect(img, 12, 12, 9, 11, DO[1])
        fill_rect(img, 18, 12, 3, 11, DO[0])
        fill_rect(img, 15, 14, 5, 7, DG[1])
        fill_rect(img, 12, 20, 9, 2, DG[1])
        px(img, 16, 20, DO[0])
        px(img, 18, 20, DO[0])
        fill_rect(img, 12, 5, 9, 8, SKIN)
        fill_rect(img, 17, 7, 4, 3, DG[1])
        fill_rect(img, 18, 8, 3, 2, (150, 200, 180))
        px(img, 19, 8, (200, 240, 220))
        draw_eyes(img, 18, 8, "right")
        fill_rect(img, 21, 14, 4, 4, DG[1])
        px(img, 22, 13, DO[0])
        px(img, 22, 12, (255, 200, 50))


def draw_demo_side(img, frame_idx):
    y_off = -3 if frame_idx == 3 else 0

    # Legs
    if frame_idx == 1:
        fill_rect(img, 10, 24, 4, 6, DG[2])
        fill_rect(img, 18, 23, 4, 6, DG[2])
    elif frame_idx == 2:
        fill_rect(img, 13, 23, 4, 6, DG[2])
        fill_rect(img, 15, 24, 4, 6, DG[2])
    else:
        fill_rect(img, 11, 24 + y_off, 4, 6, DG[2])
        fill_rect(img, 17, 24 + y_off, 4, 6, DG[2])

    # Body
    fill_rect(img, 10, 13 + y_off, 12, 10, DO[1])
    fill_rect(img, 10, 13 + y_off, 12, 3, DO[0])
    fill_rect(img, 10, 20 + y_off, 12, 3, DO[2])
    # Apron
    fill_rect(img, 12, 15 + y_off, 7, 6, DG[1])
    fill_rect(img, 12, 15 + y_off, 7, 2, DG[0])
    # Belt
    fill_rect(img, 10, 21 + y_off, 12, 2, DG[1])
    px(img, 11, 21 + y_off, DO[0])
    px(img, 14, 21 + y_off, DO[0])
    px(img, 19, 21 + y_off, DO[0])

    # Head
    fill_rect(img, 11, 5 + y_off, 10, 9, SKIN)
    fill_rect(img, 11, 11 + y_off, 10, 3, SKIN_SHADOW)
    # Goggles
    fill_rect(img, 11, 7 + y_off, 6, 3, DG[1])
    fill_rect(img, 11, 8 + y_off, 4, 2, (150, 200, 180))
    px(img, 12, 8 + y_off, (200, 240, 220))
    # Mouth
    px(img, 14, 11 + y_off, SKIN_DEEP)

    # Bomb
    if frame_idx == 4:  # wind up
        fill_rect(img, 6, 8 + y_off, 5, 5, DG[1])
        fill_rect(img, 6, 8 + y_off, 5, 2, DG[0])
        px(img, 8, 7 + y_off, DO[0])
        px(img, 8, 6 + y_off, (255, 200, 50))
        px(img, 9, 5 + y_off, (255, 255, 150))
    elif frame_idx == 5:  # throw
        fill_rect(img, 2, 5 + y_off, 4, 4, DG[1])
        fill_rect(img, 2, 5 + y_off, 4, 2, DG[0])
        px(img, 3, 4 + y_off, DO[0])
        px(img, 3, 3 + y_off, (255, 200, 50))
        px(img, 4, 2 + y_off, (255, 255, 150))
        # Trail
        px(img, 6, 7 + y_off, (255, 200, 50, 100))
        px(img, 8, 9 + y_off, (255, 200, 50, 60))
    else:
        fill_rect(img, 6, 14 + y_off, 4, 4, DG[1])
        fill_rect(img, 6, 14 + y_off, 4, 2, DG[0])
        px(img, 7, 13 + y_off, DO[0])
        px(img, 7, 12 + y_off, (255, 200, 50))


# ===================================================================
# 7. HEALER - White/Green
# ===================================================================

HEALER_WHITE = (235, 235, 240)
HEALER_GREEN = (60, 170, 80)

HW = pal(HEALER_WHITE)
HGR = pal(HEALER_GREEN)

def draw_healer_topdown(img, direction, phase):
    if direction == "down":
        # Robe bottom
        fill_rect(img, 10, 20, 12, 9, HW[1])
        fill_rect(img, 10, 20, 12, 2, HW[0])
        fill_rect(img, 10, 26, 12, 3, HW[2])
        # Green trim
        fill_rect(img, 10, 27, 12, 1, HGR[1])
        # Feet
        fill_rect(img, 12, 28, 3, 1, HW[3])
        fill_rect(img, 17, 28, 3, 1, HW[3])
        # Body
        fill_rect(img, 11, 12, 10, 9, HW[1])
        fill_rect(img, 11, 12, 10, 3, HW[0])
        fill_rect(img, 11, 18, 10, 3, HW[2])
        # Green cross emblem
        fill_rect(img, 15, 14, 2, 5, HGR[1])
        fill_rect(img, 13, 15, 6, 2, HGR[1])
        px(img, 15, 14, HGR[0])
        # Green trim on shoulders
        fill_rect(img, 11, 12, 10, 1, HGR[1])
        # Head (gentle face)
        fill_rect(img, 12, 5, 8, 8, SKIN)
        fill_rect(img, 12, 10, 8, 3, SKIN_SHADOW)
        draw_eyes(img, 16, 8, "down")
        # Gentle smile
        px(img, 14, 10, SKIN_DEEP)
        px(img, 15, 11, SKIN_DEEP)
        px(img, 16, 11, SKIN_DEEP)
        px(img, 17, 10, SKIN_DEEP)
        # Hair
        fill_rect(img, 12, 5, 8, 2, (200, 180, 130))
        # Healing staff (right side)
        fill_rect(img, 24, 6, 2, 18, (180, 160, 120))
        fill_rect(img, 24, 6, 2, 2, (200, 180, 140))
        # Green crystal on staff
        fill_rect(img, 23, 3, 4, 4, HGR[1])
        fill_rect(img, 24, 3, 2, 1, HGR[0])
        fill_rect(img, 23, 6, 4, 1, HGR[2])
        px(img, 24, 4, (150, 255, 170))  # crystal glow

    elif direction == "up":
        fill_rect(img, 10, 20, 12, 9, HW[1])
        fill_rect(img, 10, 26, 12, 3, HW[2])
        fill_rect(img, 10, 27, 12, 1, HGR[1])
        fill_rect(img, 11, 12, 10, 9, HW[1])
        fill_rect(img, 11, 12, 10, 1, HGR[1])
        fill_rect(img, 12, 5, 8, 8, (200, 180, 130))  # hair from back
        fill_rect(img, 12, 10, 8, 3, (180, 160, 110))
        fill_rect(img, 24, 6, 2, 18, (180, 160, 120))
        fill_rect(img, 23, 3, 4, 4, HGR[1])
        px(img, 24, 4, (150, 255, 170))

    elif direction == "left":
        fill_rect(img, 10, 20, 11, 9, HW[1])
        fill_rect(img, 10, 26, 11, 3, HW[2])
        fill_rect(img, 10, 27, 11, 1, HGR[1])
        fill_rect(img, 11, 12, 9, 9, HW[1])
        fill_rect(img, 11, 12, 9, 1, HGR[1])
        fill_rect(img, 11, 12, 3, 9, HW[0])
        fill_rect(img, 11, 5, 8, 8, SKIN)
        fill_rect(img, 11, 10, 8, 3, SKIN_SHADOW)
        fill_rect(img, 11, 5, 8, 2, (200, 180, 130))
        draw_eyes(img, 13, 8, "left")
        px(img, 12, 10, SKIN_DEEP)
        px(img, 13, 11, SKIN_DEEP)
        fill_rect(img, 7, 6, 2, 18, (180, 160, 120))
        fill_rect(img, 6, 3, 4, 4, HGR[1])
        px(img, 7, 4, (150, 255, 170))

    elif direction == "right":
        fill_rect(img, 11, 20, 11, 9, HW[1])
        fill_rect(img, 11, 26, 11, 3, HW[2])
        fill_rect(img, 11, 27, 11, 1, HGR[1])
        fill_rect(img, 12, 12, 9, 9, HW[1])
        fill_rect(img, 12, 12, 9, 1, HGR[1])
        fill_rect(img, 18, 12, 3, 9, HW[0])
        fill_rect(img, 13, 5, 8, 8, SKIN)
        fill_rect(img, 13, 10, 8, 3, SKIN_SHADOW)
        fill_rect(img, 13, 5, 8, 2, (200, 180, 130))
        draw_eyes(img, 18, 8, "right")
        px(img, 19, 10, SKIN_DEEP)
        px(img, 18, 11, SKIN_DEEP)
        fill_rect(img, 23, 6, 2, 18, (180, 160, 120))
        fill_rect(img, 22, 3, 4, 4, HGR[1])
        px(img, 23, 4, (150, 255, 170))


def draw_healer_side(img, frame_idx):
    y_off = -3 if frame_idx == 3 else 0

    # Robe
    fill_rect(img, 9, 21 + y_off, 14, 9, HW[1])
    fill_rect(img, 9, 21 + y_off, 14, 2, HW[0])
    fill_rect(img, 9, 27 + y_off, 14, 3, HW[2])
    fill_rect(img, 9, 28 + y_off, 14, 1, HGR[1])
    if frame_idx == 1:
        fill_rect(img, 8, 28, 3, 2, HW[2])
        fill_rect(img, 20, 27, 3, 2, HW[2])
    elif frame_idx == 2:
        fill_rect(img, 12, 28, 3, 2, HW[2])
        fill_rect(img, 16, 28, 3, 2, HW[2])

    # Upper body
    fill_rect(img, 10, 13 + y_off, 12, 9, HW[1])
    fill_rect(img, 10, 13 + y_off, 12, 3, HW[0])
    fill_rect(img, 10, 19 + y_off, 12, 3, HW[2])
    fill_rect(img, 10, 13 + y_off, 12, 1, HGR[1])
    # Cross
    fill_rect(img, 15, 15 + y_off, 2, 4, HGR[1])
    fill_rect(img, 13, 16 + y_off, 6, 2, HGR[1])

    # Head
    fill_rect(img, 11, 5 + y_off, 10, 9, SKIN)
    fill_rect(img, 11, 11 + y_off, 10, 3, SKIN_SHADOW)
    fill_rect(img, 11, 5 + y_off, 10, 2, (200, 180, 130))
    draw_eyes(img, 13, 8 + y_off, "left")
    px(img, 13, 11 + y_off, SKIN_DEEP)
    px(img, 14, 12 + y_off, SKIN_DEEP)

    # Staff
    if frame_idx in (4, 5):
        fill_rect(img, 4, 6 + y_off, 7, 2, (180, 160, 120))
        fill_rect(img, 2, 3 + y_off, 4, 5, HGR[1])
        fill_rect(img, 3, 3 + y_off, 2, 1, HGR[0])
        px(img, 3, 5 + y_off, (150, 255, 170))
        if frame_idx == 5:
            # Healing glow
            for dx in range(-2, 5):
                for dy in range(-2, 5):
                    xx, yy = 3 + dx, 5 + y_off + dy
                    if 0 <= xx < 32 and 0 <= yy < 32:
                        existing = img.getpixel((xx, yy))
                        if existing[3] == 0:
                            px(img, xx, yy, (100, 255, 130, 60))
    else:
        fill_rect(img, 6, 3 + y_off, 2, 22, (180, 160, 120))
        fill_rect(img, 5, 0 + y_off, 4, 4, HGR[1])
        fill_rect(img, 6, 0 + y_off, 2, 1, HGR[0])
        fill_rect(img, 5, 3 + y_off, 4, 1, HGR[2])
        px(img, 6, 1 + y_off, (150, 255, 170))


# ===================================================================
# 8. DONUT BUDDY - Adventure Time style (24x24 frames)
# ===================================================================

DONUT_BODY = (200, 160, 80)
DONUT_DARK = (160, 120, 50)
DONUT_LIGHT = (230, 195, 120)
DONUT_DEEP = (120, 85, 35)
FROSTING = (255, 150, 180)
FROST_LIGHT = (255, 190, 210)
FROST_DARK = (220, 110, 140)
SPRINKLE_COLORS = [(255, 80, 80), (80, 200, 80), (80, 80, 255), (255, 255, 80), (255, 140, 50)]

def draw_donut_buddy(img, frame_idx):
    """0=idle, 1=walk1, 2=walk2, 3=happy, 4=wave, 5=jump"""
    cx, cy = 12, 11
    y_off = -2 if frame_idx == 5 else 0

    # Stubby legs
    if frame_idx == 1:
        fill_rect(img, 8, 19 + y_off, 3, 4, DONUT_BODY)
        fill_rect(img, 13, 18 + y_off, 3, 4, DONUT_BODY)
        fill_rect(img, 8, 21 + y_off, 3, 2, DONUT_DARK)
        fill_rect(img, 13, 20 + y_off, 3, 2, DONUT_DARK)
    elif frame_idx == 2:
        fill_rect(img, 9, 18 + y_off, 3, 4, DONUT_BODY)
        fill_rect(img, 12, 19 + y_off, 3, 4, DONUT_BODY)
        fill_rect(img, 9, 20 + y_off, 3, 2, DONUT_DARK)
        fill_rect(img, 12, 21 + y_off, 3, 2, DONUT_DARK)
    elif frame_idx == 5:  # jump - legs tucked
        fill_rect(img, 9, 18 + y_off, 3, 3, DONUT_BODY)
        fill_rect(img, 12, 18 + y_off, 3, 3, DONUT_BODY)
    else:
        fill_rect(img, 8, 18 + y_off, 3, 4, DONUT_BODY)
        fill_rect(img, 13, 18 + y_off, 3, 4, DONUT_BODY)
        fill_rect(img, 8, 20 + y_off, 3, 2, DONUT_DARK)
        fill_rect(img, 13, 20 + y_off, 3, 2, DONUT_DARK)

    # Donut ring body - golden brown torus shape
    # Outer ring
    fill_rect(img, 5, 5 + y_off, 14, 14, DONUT_BODY)
    # Round the corners
    for corner in [(5, 5), (5, 6), (6, 5),
                   (18, 5), (17, 5), (18, 6),
                   (5, 18), (5, 17), (6, 18),
                   (18, 18), (17, 18), (18, 17)]:
        px(img, corner[0], corner[1] + y_off, TRANSP)

    # Donut hole (center)
    fill_rect(img, 9, 9 + y_off, 6, 5, DONUT_DARK)
    fill_rect(img, 10, 8 + y_off, 4, 7, DONUT_DARK)
    # Inner hole shadow
    fill_rect(img, 10, 10 + y_off, 4, 3, DONUT_DEEP)
    fill_rect(img, 11, 9 + y_off, 2, 5, DONUT_DEEP)

    # Shading on body
    # Highlight (top-right)
    fill_rect(img, 12, 5 + y_off, 5, 2, DONUT_LIGHT)
    fill_rect(img, 16, 7 + y_off, 2, 3, DONUT_LIGHT)
    # Shadow (bottom-left)
    fill_rect(img, 6, 14 + y_off, 4, 3, DONUT_DARK)
    fill_rect(img, 6, 10 + y_off, 2, 4, DONUT_DARK)
    # Deep shadow bottom
    fill_rect(img, 7, 16 + y_off, 10, 2, DONUT_DARK)

    # Pink frosting on top half
    fill_rect(img, 7, 5 + y_off, 10, 4, FROSTING)
    fill_rect(img, 6, 6 + y_off, 12, 3, FROSTING)
    # Frosting drips
    px(img, 7, 9 + y_off, FROSTING)
    px(img, 11, 9 + y_off, FROSTING)
    px(img, 15, 9 + y_off, FROSTING)
    px(img, 17, 9 + y_off, FROSTING)
    # Frosting highlight
    fill_rect(img, 9, 5 + y_off, 4, 2, FROST_LIGHT)
    fill_rect(img, 14, 6 + y_off, 3, 1, FROST_LIGHT)
    # Frosting shadow
    fill_rect(img, 6, 8 + y_off, 2, 1, FROST_DARK)
    fill_rect(img, 16, 8 + y_off, 2, 1, FROST_DARK)

    # Sprinkles on frosting
    sprinkle_positions = [(8, 6), (10, 5), (13, 5), (15, 6), (9, 7), (12, 7), (16, 7)]
    for i, (sx, sy) in enumerate(sprinkle_positions):
        color = SPRINKLE_COLORS[i % len(SPRINKLE_COLORS)]
        px(img, sx, sy + y_off, color)

    # Cute face - on the donut body below the hole
    face_y = 14 + y_off
    # Big cute dot eyes (above the hole, on the frosting area)
    eye_y = 7 + y_off
    # Actually place eyes on the lower body part for Adventure Time style
    eye_y = 14 + y_off
    # Dot eyes
    px(img, 10, eye_y, BLACK)
    px(img, 11, eye_y, BLACK)
    px(img, 13, eye_y, BLACK)
    px(img, 14, eye_y, BLACK)
    # Eye highlights
    px(img, 10, eye_y, (40, 40, 50))
    px(img, 13, eye_y, (40, 40, 50))
    px(img, 11, eye_y - 1, (255, 255, 255))  # cute sparkle
    px(img, 14, eye_y - 1, (255, 255, 255))

    # Big smile
    if frame_idx == 3:  # extra happy
        px(img, 9, 15 + y_off, DONUT_DEEP)
        fill_rect(img, 10, 16 + y_off, 4, 1, DONUT_DEEP)
        px(img, 14, 15 + y_off, DONUT_DEEP)
        # Open mouth
        fill_rect(img, 10, 15 + y_off, 4, 2, (180, 60, 70))
        fill_rect(img, 11, 15 + y_off, 2, 1, (255, 255, 255))  # teeth
    else:
        px(img, 9, 16 + y_off, DONUT_DEEP)
        fill_rect(img, 10, 16 + y_off, 4, 1, DONUT_DEEP)
        px(img, 14, 16 + y_off, DONUT_DEEP)

    # Stubby arms
    if frame_idx == 4:  # wave
        # Left arm normal
        fill_rect(img, 3, 11 + y_off, 3, 3, DONUT_BODY)
        fill_rect(img, 3, 12 + y_off, 3, 1, DONUT_DARK)
        # Right arm up waving
        fill_rect(img, 18, 7 + y_off, 3, 3, DONUT_BODY)
        fill_rect(img, 19, 6 + y_off, 2, 2, DONUT_BODY)
        fill_rect(img, 18, 9 + y_off, 3, 1, DONUT_DARK)
    elif frame_idx == 3:  # happy - arms up
        fill_rect(img, 3, 8 + y_off, 3, 4, DONUT_BODY)
        fill_rect(img, 3, 10 + y_off, 3, 2, DONUT_DARK)
        fill_rect(img, 18, 8 + y_off, 3, 4, DONUT_BODY)
        fill_rect(img, 18, 10 + y_off, 3, 2, DONUT_DARK)
    else:
        # Normal arms at sides
        fill_rect(img, 3, 11 + y_off, 3, 4, DONUT_BODY)
        fill_rect(img, 3, 13 + y_off, 3, 2, DONUT_DARK)
        fill_rect(img, 18, 11 + y_off, 3, 4, DONUT_BODY)
        fill_rect(img, 18, 13 + y_off, 3, 2, DONUT_DARK)


# ===================================================================
# GENERATE ALL SPRITES
# ===================================================================

def main():
    print("Generating character sprites...")

    # 1. Melee Knight
    print("  [1/15] melee_topdown.png")
    sheet = make_topdown_sheet(draw_knight_topdown)
    sheet.save(os.path.join(OUT, "melee_topdown.png"))

    print("  [2/15] melee_side.png")
    sheet = make_side_sheet(draw_knight_side, 6, 32)
    sheet.save(os.path.join(OUT, "melee_side.png"))

    # 2. Ranged Ranger
    print("  [3/15] ranged_topdown.png")
    sheet = make_topdown_sheet(draw_ranger_topdown)
    sheet.save(os.path.join(OUT, "ranged_topdown.png"))

    print("  [4/15] ranged_side.png")
    sheet = make_side_sheet(draw_ranger_side, 6, 32)
    sheet.save(os.path.join(OUT, "ranged_side.png"))

    # 3. Mage Wizard
    print("  [5/15] mage_topdown.png")
    sheet = make_topdown_sheet(draw_mage_topdown)
    sheet.save(os.path.join(OUT, "mage_topdown.png"))

    print("  [6/15] mage_side.png")
    sheet = make_side_sheet(draw_mage_side, 6, 32)
    sheet.save(os.path.join(OUT, "mage_side.png"))

    # 4. Summoner
    print("  [7/15] summoner_topdown.png")
    sheet = make_topdown_sheet(draw_summoner_topdown)
    sheet.save(os.path.join(OUT, "summoner_topdown.png"))

    print("  [8/15] summoner_side.png")
    sheet = make_side_sheet(draw_summoner_side, 6, 32)
    sheet.save(os.path.join(OUT, "summoner_side.png"))

    # 5. Rogue
    print("  [9/15] rogue_topdown.png")
    sheet = make_topdown_sheet(draw_rogue_topdown)
    sheet.save(os.path.join(OUT, "rogue_topdown.png"))

    print("  [10/15] rogue_side.png")
    sheet = make_side_sheet(draw_rogue_side, 6, 32)
    sheet.save(os.path.join(OUT, "rogue_side.png"))

    # 6. Demolitionist
    print("  [11/15] demolitionist_topdown.png")
    sheet = make_topdown_sheet(draw_demo_topdown)
    sheet.save(os.path.join(OUT, "demolitionist_topdown.png"))

    print("  [12/15] demolitionist_side.png")
    sheet = make_side_sheet(draw_demo_side, 6, 32)
    sheet.save(os.path.join(OUT, "demolitionist_side.png"))

    # 7. Healer
    print("  [13/15] healer_topdown.png")
    sheet = make_topdown_sheet(draw_healer_topdown)
    sheet.save(os.path.join(OUT, "healer_topdown.png"))

    print("  [14/15] healer_side.png")
    sheet = make_side_sheet(draw_healer_side, 6, 32)
    sheet.save(os.path.join(OUT, "healer_side.png"))

    # 8. Donut Buddy
    print("  [15/15] donut_buddy.png")
    sheet = make_side_sheet(draw_donut_buddy, 6, 24)
    sheet.save(os.path.join(OUT, "donut_buddy.png"))

    # Verify all files
    print("\nVerifying output files:")
    expected = [
        ("melee_topdown.png", 128, 128),
        ("melee_side.png", 192, 32),
        ("ranged_topdown.png", 128, 128),
        ("ranged_side.png", 192, 32),
        ("mage_topdown.png", 128, 128),
        ("mage_side.png", 192, 32),
        ("summoner_topdown.png", 128, 128),
        ("summoner_side.png", 192, 32),
        ("rogue_topdown.png", 128, 128),
        ("rogue_side.png", 192, 32),
        ("demolitionist_topdown.png", 128, 128),
        ("demolitionist_side.png", 192, 32),
        ("healer_topdown.png", 128, 128),
        ("healer_side.png", 192, 32),
        ("donut_buddy.png", 144, 24),
    ]

    all_ok = True
    for fname, exp_w, exp_h in expected:
        fpath = os.path.join(OUT, fname)
        if not os.path.exists(fpath):
            print(f"  MISSING: {fname}")
            all_ok = False
            continue
        img = Image.open(fpath)
        w, h = img.size
        status = "OK" if (w == exp_w and h == exp_h) else f"WRONG SIZE ({w}x{h})"
        print(f"  {fname}: {w}x{h} - {status}")
        if w != exp_w or h != exp_h:
            all_ok = False

    if all_ok:
        print(f"\nAll 15 sprite files generated successfully in {OUT}")
    else:
        print("\nSome files had issues!")

if __name__ == "__main__":
    main()
