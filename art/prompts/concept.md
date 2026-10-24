# Референсы для 3D-моделей

Файл собран скриптом `tools/art.py prompts` из `art/manifest.json` — правки вносите туда.
Каждый запрос копируйте целиком. Результат сохраняйте в `art/inbox/<id>.png`.

## factory_top

Итог: 848×1264 → `art/references/factory_top.png`

```
Purpose: a reference image of one building for a mobile puzzle game about building roads on a square grid. A 3D model will be built from it, so the layout must be exact and easy to read.

View: strictly top-down orthographic, the camera looks straight down. No perspective, no isometric angle, no visible side walls, no tilt.

Style: clean low-poly game art. Every surface is one solid flat color; roof parts at different heights are told apart only by slightly lighter or darker flat tones. Few large shapes that stay readable on a phone screen.

Palette: ground #F4EFE6, asphalt #7C7C84, markings #F4EFE6, greenery #8CC084, plus the building colors named below.

Constraints: no gradients, no textures, no noise, no cast shadows, no ambient occlusion, no outlines, no people, no vehicles. No text, letters, numbers or logos anywhere. Do not draw the grid lines themselves.

Subject: A yellow factory whose footprint is exactly a rectangle of 2 by 3 equal square cells: 2 cells wide, 3 cells tall. The footprint fills the whole image, leaving only a thin even margin of plain ground #F4EFE6 around it.

Cell layout, as an invisible 2×3 grid:
- top row, both cells: factory building;
- middle row, both cells: factory building;
- bottom row, right cell: factory building;
- bottom row, left cell: an open yard with no roof over it.
The building is one solid L-shaped block over its five cells, with no gaps between cells.

Building: flat roof #F2B33D with a lighter yellow rim #F7CF7A along the roof edge. On the roof: two round chimneys in dark yellow #C28F2A in the top part, a row of small square vents and one long skylight strip. A loading dock door in the building wall faces the yard.

Yard: asphalt #7C7C84 with three short parking lines #F4EFE6, surrounded on its two outer sides by a low fence. The gate is a wide opening across the bottom edge of the yard, on the outer edge of the footprint: a road will connect to it later, so nothing blocks the opening.
```
