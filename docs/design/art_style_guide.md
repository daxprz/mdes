# Art Style Guide

## Overall Style
- 16-bit retro pixel art (think Celeste meets bakery theme)
- Warm, colorful palette - nothing too dark or gritty
- All bakery/candy/sweets themed
- 1px dark outlines on all characters and important objects
- 3-4 shading tones per color area (highlight, base, shadow, deep shadow)
- Dithering for gradients where appropriate

## Color Palettes Per Class
| Class | Primary | Secondary | Accent |
|-------|---------|-----------|--------|
| Melee | Steel blue | Silver gray | Gold trim |
| Ranged | Forest green | Leather brown | Cream |
| Mage | Royal purple | Deep gold | Cyan glow |
| Summoner | Warm orange | Sunny yellow | Pink |
| Rogue | Dark crimson | Charcoal black | Blood red |

## Sprite Sizes
| Asset | Size | Format |
|-------|------|--------|
| Characters (topdown) | 32x32 per frame, 128x128 sheet | 4 cols x 4 rows |
| Characters (side) | 32x32 per frame, 192x32 sheet | 6 cols x 1 row |
| Enemies | 32x32 per frame | 4 frame walk cycle |
| Bosses | 64x64 per frame, 256x64 sheet | 4 frames |
| Items | 16x16 | Single or 4-frame anim |
| Tiles | 16x16 | 10x10 grid tileset |
| Donut buddy | 24x24 per frame, 144x24 sheet | 6 frames |
| UI icons | 16x16 | Single frame |

## Animation Guidelines
- Walk cycles: 4 frames, smooth weight shift
- Attack animations: 2 frames (windup + strike), snappy
- Idle: subtle breathing or sway (1-2 px movement)
- Death: shrink + fade (handled in code)

## Environment Themes
| Area | Palette | Details |
|------|---------|---------|
| Overworld valley | Lush greens, earthy browns | Grass, flowers, paths |
| Tower 1 (Gingerbread) | Warm browns, white icing | Cookie walls, candy decorations |
| Tower 2 (Icing) | Pastel pinks/blues/whites | Frosting drips, fondant platforms |
| Tower 3 (Sprinkle) | Rainbow colors, confetti | Sprinkle-covered everything |
| Final Tower (Muffin) | Golden browns, deep reds | Muffin architecture, crumb debris |
