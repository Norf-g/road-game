"""Конвейер картинок из Gemini для «Города дорог».

Источник правды — art/manifest.json: стили запросов и список всех картинок.

    python tools/art.py prompts          # собрать готовые запросы в art/prompts/<стиль>.md
    python tools/art.py status           # что уже готово, а что нет
    python tools/art.py process [id ...] # обработать картинки из art/inbox/ и положить в игру
    python tools/art.py process --force  # переобработать, даже если результат свежее исходника

Обработка:
- фон «transparent»: цвет фона берётся с краёв картинки (Gemini рисует пурпурный #FF00FF, но
  не всегда точно), всё близкое к нему становится прозрачным с мягким краем, с полупрозрачных
  пикселей снимается пурпурный оттенок; затем картинка обрезается по содержимому и вписывается
  в нужный размер с отступом;
- фон «opaque»: картинка обрезается по центру до нужных пропорций и уменьшается;
- «recolor_dark» у выхода: тёмные (графитовые) части перекрашиваются в заданный цвет — так иконки
  для тёмных кнопок становятся белыми, а цветной акцент иконок улучшений остаётся. Серые и белые
  детали внутри глифа (разметка дороги, лампы светофора) становятся прорезями, иначе слились бы с белым.

Запускать из корня репозитория интерпретатором tools/.venv (там установлен Pillow).
"""

import argparse
import json
import statistics
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "art" / "manifest.json"
INBOX = ROOT / "art" / "inbox"
PROMPTS = ROOT / "art" / "prompts"
SOURCE_EXTENSIONS = (".png", ".jpg", ".jpeg", ".webp")

# Расстояние до цвета фона (0..441): ближе KEY_INNER — полностью прозрачно, дальше KEY_OUTER — непрозрачно.
KEY_INNER = 60.0
KEY_OUTER = 140.0
DEFAULT_PADDING = 0.06

# recolor_dark: пиксели темнее DARK_LUMA (0..255) — графитовый глиф, перекрашиваются; более светлые
# серые (насыщенность ниже GREY_SATURATION) — прорези; насыщенные цветные — акцент, остаются.
DARK_LUMA = 85
GREY_SATURATION = 40

# Фон адаптивной иконки Android — ровный цвет земли из палитры.
ICON_BACKGROUND = {"path": "game/assets/app/icon_background_432.png", "size": (432, 432), "color": "#F4EFE6"}

STYLE_TITLES = {
    "icon": "Иконки интерфейса",
    "upgrade": "Иконки улучшений",
    "app_icon": "Иконка приложения",
    "icon_layer": "Слой адаптивной иконки Android",
    "emblem": "Эмблема для меню",
    "banner": "Баннер для магазина",
}


def load_manifest() -> dict:
    return json.loads(MANIFEST.read_text(encoding="utf-8"))


def compose_prompt(manifest: dict, item: dict) -> str:
    return f"{manifest['styles'][item['style']]}\n\nSubject: {item['subject']}"


def find_source(item_id: str) -> Path | None:
    for extension in SOURCE_EXTENSIONS:
        path = INBOX / f"{item_id}{extension}"
        if path.exists():
            return path
    return None


def is_done(item: dict) -> bool:
    return all((ROOT / output["path"]).exists() for output in item["outputs"])


def cmd_prompts(manifest: dict) -> None:
    PROMPTS.mkdir(parents=True, exist_ok=True)
    by_style: dict[str, list[dict]] = {}
    for item in manifest["items"]:
        by_style.setdefault(item["style"], []).append(item)
    for style, items in by_style.items():
        lines = [
            f"# {STYLE_TITLES.get(style, style)}",
            "",
            "Файл собран скриптом `tools/art.py prompts` из `art/manifest.json` — правки вносите туда.",
            "Каждый запрос копируйте целиком. Результат сохраняйте в `art/inbox/<id>.png`.",
        ]
        if len(items) > 1:
            lines.append(
                "Когда первая картинка группы удалась, положите её в `art/references/` и прикладывайте к остальным "
                "запросам группы с фразой: «Match the style of the attached image exactly»."
            )
        for item in items:
            sizes = ", ".join(f"{o['size'][0]}×{o['size'][1]} → `{o['path']}`" for o in item["outputs"])
            lines += ["", f"## {item['id']}", "", f"Итог: {sizes}", "", "```", compose_prompt(manifest, item), "```"]
        (PROMPTS / f"{style}.md").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
        print(f"art/prompts/{style}.md: {len(items)}")


def cmd_status(manifest: dict) -> None:
    done = 0
    for item in manifest["items"]:
        ready = is_done(item)
        done += ready
        source = find_source(item["id"])
        state = "готово" if ready else ("есть в inbox, нужна обработка" if source else "нужно сгенерировать")
        print(f"{'+' if ready else '-'} {item['id']:<22} {state}")
    print(f"\nГотово {done} из {len(manifest['items'])}")


def _pixels(image: Image.Image):
    """Пиксели построчно; в Pillow 12+ getdata устарела."""
    flattened = getattr(image, "get_flattened_data", None)
    return flattened() if flattened else image.getdata()


def background_color(image: Image.Image) -> tuple[int, int, int]:
    """Медианный цвет полосы в несколько пикселей по краю картинки."""
    rgb = image.convert("RGB")
    width, height = rgb.size
    band = max(2, min(width, height) // 100)
    samples = []
    for x in range(0, width, 4):
        for y in list(range(band)) + list(range(height - band, height)):
            samples.append(rgb.getpixel((x, y)))
    for y in range(0, height, 4):
        for x in list(range(band)) + list(range(width - band, width)):
            samples.append(rgb.getpixel((x, y)))
    return tuple(int(statistics.median(channel)) for channel in zip(*samples))


def key_out(image: Image.Image) -> Image.Image:
    """Убирает фон: прозрачность по расстоянию до цвета фона, без пурпурной каймы на краях."""
    bg = background_color(image)
    source = image.convert("RGB")
    result = Image.new("RGBA", source.size)
    out = []
    for r, g, b in _pixels(source):
        distance = ((r - bg[0]) ** 2 + (g - bg[1]) ** 2 + (b - bg[2]) ** 2) ** 0.5
        alpha = min(max((distance - KEY_INNER) / (KEY_OUTER - KEY_INNER), 0.0), 1.0)
        if alpha <= 0.0:
            out.append((0, 0, 0, 0))
            continue
        if alpha < 1.0:
            # Полупрозрачный край — смесь цвета иконки с фоном; убираем вклад фона.
            r, g, b = (
                min(max(round((channel - (1.0 - alpha) * bg_channel) / alpha), 0), 255)
                for channel, bg_channel in ((r, bg[0]), (g, bg[1]), (b, bg[2]))
            )
        out.append((r, g, b, round(alpha * 255)))
    result.putdata(out)
    return result


def fit_transparent(image: Image.Image, size: tuple[int, int], padding: float) -> Image.Image:
    box = image.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
    if box is None:
        raise ValueError("после удаления фона картинка пустая")
    content = image.crop(box)
    inner = (size[0] * (1 - 2 * padding), size[1] * (1 - 2 * padding))
    scale = min(inner[0] / content.width, inner[1] / content.height)
    content = content.resize((max(1, round(content.width * scale)), max(1, round(content.height * scale))), Image.LANCZOS)
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    canvas.paste(content, ((size[0] - content.width) // 2, (size[1] - content.height) // 2), content)
    return canvas


def fit_opaque(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    rgb = image.convert("RGB")
    target = size[0] / size[1]
    if rgb.width / rgb.height > target:
        width = round(rgb.height * target)
        left = (rgb.width - width) // 2
        rgb = rgb.crop((left, 0, left + width, rgb.height))
    else:
        height = round(rgb.width / target)
        top = (rgb.height - height) // 2
        rgb = rgb.crop((0, top, rgb.width, top + height))
    return rgb.resize(size, Image.LANCZOS)


def recolor_dark(image: Image.Image, color: str) -> Image.Image:
    target = Image.new("RGB", (1, 1), color).getpixel((0, 0))
    out = []
    for r, g, b, a in _pixels(image):
        luma = 0.299 * r + 0.587 * g + 0.114 * b
        if a and luma < DARK_LUMA:
            out.append((*target, a))
        elif a and max(r, g, b) - min(r, g, b) < GREY_SATURATION:
            out.append((0, 0, 0, 0))
        else:
            out.append((r, g, b, a))
    result = Image.new("RGBA", image.size)
    result.putdata(out)
    return result


def process_item(item: dict, source: Path) -> None:
    image = Image.open(source)
    keyed = key_out(image) if item["background"] == "transparent" else None
    for output in item["outputs"]:
        size = tuple(output["size"])
        if keyed is not None:
            result = fit_transparent(keyed, size, output.get("padding", DEFAULT_PADDING))
            if "recolor_dark" in output:
                result = recolor_dark(result, output["recolor_dark"])
        else:
            result = fit_opaque(image, size)
        path = ROOT / output["path"]
        path.parent.mkdir(parents=True, exist_ok=True)
        result.save(path, optimize=True)
        print(f"  -> {output['path']} ({size[0]}×{size[1]})")


def ensure_icon_background() -> None:
    path = ROOT / ICON_BACKGROUND["path"]
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        Image.new("RGB", ICON_BACKGROUND["size"], ICON_BACKGROUND["color"]).save(path)
        print(f"  -> {ICON_BACKGROUND['path']} (ровный цвет)")


def cmd_process(manifest: dict, ids: list[str], force: bool) -> int:
    ensure_icon_background()
    known = {item["id"]: item for item in manifest["items"]}
    unknown = [item_id for item_id in ids if item_id not in known]
    if unknown:
        print(f"Нет в манифесте: {', '.join(unknown)}")
        return 1
    failures = 0
    for item in manifest["items"]:
        if ids and item["id"] not in ids:
            continue
        source = find_source(item["id"])
        if source is None:
            continue
        outputs = [ROOT / output["path"] for output in item["outputs"]]
        fresh = all(path.exists() and path.stat().st_mtime >= source.stat().st_mtime for path in outputs)
        if fresh and not force:
            continue
        print(f"{item['id']} <- {source.relative_to(ROOT)}")
        try:
            process_item(item, source)
        except Exception as error:  # одна битая картинка не должна останавливать остальные
            failures += 1
            print(f"  ошибка: {error}")
    return 1 if failures else 0


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("prompts")
    sub.add_parser("status")
    process = sub.add_parser("process")
    process.add_argument("ids", nargs="*")
    process.add_argument("--force", action="store_true")
    args = parser.parse_args()

    manifest = load_manifest()
    if args.command == "prompts":
        cmd_prompts(manifest)
    elif args.command == "status":
        cmd_status(manifest)
    else:
        return cmd_process(manifest, args.ids, args.force)
    return 0


if __name__ == "__main__":
    sys.exit(main())
