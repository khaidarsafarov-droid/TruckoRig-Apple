#!/usr/bin/env python3
"""Render App Store phone frames 06_premium and 07_analytics.

Same caption plate as the Android listing frames: Midnight & Gold canvas,
white headline, gold subtitle, phone on the lower half. Sizes are the App
Store 6.9-inch and 6.5-inch slots. Wording stays on the App Store.

    python3 Tools/render_app_store_screenshots.py
    python3 Tools/render_app_store_screenshots.py --check
"""

from __future__ import annotations

import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "store" / "app-store"
FONTS = ROOT / "TruckoRig" / "Resources" / "Fonts"

SIZES = {
    "iphone-6.9": (1320, 2868),
    "iphone-6.5": (1284, 2778),
}

SLIDES = ("06_premium", "07_analytics")

COPY = {
    "premium_title": "First month free",
    "premium_subtitle": "Then $2.99/month",
    "analytics_title": "Premium numbers",
    "analytics_subtitle": "Paycheck, diesel, and the routes that paid",
    "paywall_title": "TruckoRig Premium",
    "paywall_body": "The first month is free. After that, the App Store charges $2.99 a month in the United States.",
    "paywall_terms": "Renews every month in the App Store until you cancel.",
    "subscribe": "Try 1 month free",
    "restore": "Restore purchases",
    "analytics_heading": "My numbers",
    "analytics_sub": "Paychecks, diesel and routes",
    "premium_badge": "Premium",
    "paycheck": "Paycheck",
    "paycheck_value": "$11,605.90",
    "diesel": "Diesel",
    "diesel_value": "$315.27",
    "gallons": "Gallons",
    "gallons_value": "86.4",
    "weeks": "Money by week",
    "routes": "Top routes",
    "route_1": "Aurora, CO  →  Arlington, WA",
    "route_1_value": "$3,815.90",
    "route_2": "Kansas City, MO  →  Phoenix, AZ",
    "route_2_value": "$2,890.00",
    "route_3": "Garner, NC  →  Dallas, TX",
    "route_3_value": "$2,500.00",
}

WEEKS = [8240, 9180, 7640, 10220, 8860, 9740, 10410, 11606]
WEEK_LABELS = ["W36", "W37", "W38", "W39", "W40", "W41", "W42", "W43"]

NAVY = (30, 33, 80)
NAVY_MID = (23, 26, 66)
NAVY_END = (15, 18, 48)
PAGE = (245, 244, 241)
CARD = (253, 252, 250)
INK = (22, 24, 43)
MUTED = (88, 90, 110)
GOLD = (200, 168, 103)
GOLD_SOFT = (228, 211, 168)
GOLD_DEEP = (212, 188, 133)
ON_GOLD = (29, 23, 8)
WHITE = (255, 255, 255)
HERO = (30, 34, 80)


def png_size(path: Path) -> tuple[int, int]:
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path} is not a PNG")
    length, kind = struct.unpack(">I4s", data[8:16])
    if kind != b"IHDR" or length < 8:
        raise SystemExit(f"{path} has no IHDR")
    width, height = struct.unpack(">II", data[16:24])
    return width, height


def check() -> int:
    problems: list[str] = []
    for text in COPY.values():
        if "Play" in text:
            problems.append(f"listing copy mentions Play: {text}")
    for folder, (width, height) in SIZES.items():
        for slide in SLIDES:
            path = OUT / folder / f"{slide}.png"
            if not path.is_file():
                problems.append(f"missing {path.relative_to(ROOT)}")
                continue
            actual = png_size(path)
            if actual != (width, height):
                problems.append(f"{path.relative_to(ROOT)} is {actual[0]}x{actual[1]}, expected {width}x{height}")
    if problems:
        for problem in problems:
            print(f"error: {problem}")
        return 1
    print(f"App Store frames OK — {len(SIZES) * len(SLIDES)} PNGs, 6.9-inch and 6.5-inch")
    return 0


def font(name: str, size: int):
    from PIL import ImageFont

    return ImageFont.truetype(str(FONTS / name), size)


def gradient(size: tuple[int, int]):
    from PIL import Image

    width, height = size
    column = Image.new("RGB", (1, height))
    pixels = column.load()
    stops = [(0.0, (42, 45, 102)), (0.42, NAVY), (1.0, NAVY_END)]
    for y in range(height):
        t = y / max(height - 1, 1)
        pixels[0, y] = mix_stops(stops, t)
    image = column.resize(size)
    return image


def mix_stops(stops, t: float) -> tuple[int, int, int]:
    for (left, color_a), (right, color_b) in zip(stops, stops[1:]):
        if t <= right:
            span = max(right - left, 1e-6)
            return mix(color_a, color_b, (t - left) / span)
    return stops[-1][1]


def mix(a, b, t: float) -> tuple[int, int, int]:
    t = max(0.0, min(1.0, t))
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def text_width(draw, value: str, face) -> int:
    return int(draw.textlength(value, font=face))


def centered(draw, value: str, face, y: int, width: int, fill) -> None:
    x = (width - text_width(draw, value, face)) / 2
    draw.text((x, y), value, font=face, fill=fill)


def rounded(draw, box, radius: int, fill) -> None:
    draw.rounded_rectangle(box, radius=radius, fill=fill)


def phone_chrome(base, draw, box, title: str, subtitle: str, badge: str) -> tuple[int, int, int, int]:
    """Draws the device and returns the screen content box (x, y, right, bottom)."""
    x0, y0, x1, y1 = box
    bezel = max(12, (x1 - x0) // 48)
    rounded(draw, box, (x1 - x0) // 8, (22, 25, 41))
    screen = (x0 + bezel, y0 + bezel, x1 - bezel, y1 - bezel)
    rounded(draw, screen, (x1 - x0) // 10, PAGE)
    sx0, sy0, sx1, sy1 = screen
    width = sx1 - sx0
    notch_w = width // 4
    notch = (sx0 + (width - notch_w) / 2, sy0 + 10, sx0 + (width + notch_w) / 2, sy0 + 28)
    draw.rounded_rectangle(notch, radius=10, fill=(11, 13, 28))
    status = font("DMSans-Medium.ttf", max(16, width // 28))
    draw.text((sx0 + 28, sy0 + 18), "9:41", font=status, fill=INK)
    draw.text((sx1 - 90, sy0 + 18), "5G", font=status, fill=INK)
    return sx0 + 8, sy0 + 56, sx1 - 8, sy1 - 16


def draw_premium(image, draw, screen) -> None:
    sx0, sy0, sx1, sy1 = screen
    width = sx1 - sx0
    pad = width // 18
    title = font("DMSans-Bold.ttf", max(28, width // 16))
    body = font("Roboto-Regular.ttf", max(20, width // 26))
    small = font("Roboto-Regular.ttf", max(16, width // 32))
    button = font("DMSans-Bold.ttf", max(22, width // 24))
    y = sy0 + 12
    draw.text((sx0 + pad, y), COPY["paywall_title"], font=title, fill=INK)
    y += int(title.size * 1.7)
    card = (sx0 + pad, y, sx1 - pad, y + int(width * 1.15))
    rounded(draw, card, 28, CARD)
    text_x = card[0] + 28
    text_right = card[2] - 28
    cursor = card[1] + 28
    cursor = wrap(draw, COPY["paywall_body"], body, text_x, cursor, text_right - text_x, INK, 8)
    cursor += 16
    cursor = wrap(draw, COPY["paywall_terms"], small, text_x, cursor, text_right - text_x, MUTED, 6)
    cursor += 28
    button_box = (text_x, cursor, text_right, cursor + int(button.size * 2.6))
    rounded(draw, button_box, 22, GOLD)
    centered_in(draw, COPY["subscribe"], button, button_box, ON_GOLD)
    cursor = button_box[3] + 18
    centered_in(draw, COPY["restore"], body, (text_x, cursor, text_right, cursor + int(body.size * 2)), MUTED)


def draw_analytics(image, draw, screen) -> None:
    sx0, sy0, sx1, sy1 = screen
    width = sx1 - sx0
    pad = width // 18
    title = font("DMSans-Bold.ttf", max(28, width // 16))
    sub = font("Roboto-Regular.ttf", max(18, width // 30))
    label = font("DMSans-Medium.ttf", max(16, width // 32))
    value = font("DMSans-Bold.ttf", max(26, width // 18))
    y = sy0 + 8
    draw.text((sx0 + pad, y), COPY["analytics_heading"], font=title, fill=INK)
    badge = font("DMSans-Bold.ttf", max(14, width // 36))
    badge_w = text_width(draw, COPY["premium_badge"], badge) + 36
    badge_box = (sx1 - pad - badge_w, y + 6, sx1 - pad, y + int(badge.size * 2.2))
    rounded(draw, badge_box, 14, GOLD)
    centered_in(draw, COPY["premium_badge"], badge, badge_box, ON_GOLD)
    y += int(title.size * 1.35)
    draw.text((sx0 + pad, y), COPY["analytics_sub"], font=sub, fill=MUTED)
    y += int(sub.size * 2.2)
    card_h = int(width * 0.42)
    card = (sx0 + pad, y, sx1 - pad, y + card_h)
    rounded(draw, card, 28, HERO)
    col = (card[2] - card[0]) / 3
    stats = (
        (COPY["paycheck"], COPY["paycheck_value"]),
        (COPY["diesel"], COPY["diesel_value"]),
        (COPY["gallons"], COPY["gallons_value"]),
    )
    for index, (name, amount) in enumerate(stats):
        cx = card[0] + col * index + 24
        draw.text((cx, card[1] + 28), name, font=label, fill=GOLD_SOFT)
        draw.text((cx, card[1] + 28 + int(label.size * 1.8)), amount, font=value, fill=WHITE)
    y = card[3] + 22
    chart_h = int(width * 0.48)
    chart = (sx0 + pad, y, sx1 - pad, y + chart_h)
    rounded(draw, chart, 28, CARD)
    draw.text((chart[0] + 24, chart[1] + 18), COPY["weeks"], font=label, fill=INK)
    bars(draw, chart, WEEKS, WEEK_LABELS)
    y = chart[3] + 22
    routes = (sx0 + pad, y, sx1 - pad, sy1 - 8)
    rounded(draw, routes, 28, CARD)
    draw.text((routes[0] + 24, routes[1] + 18), COPY["routes"], font=label, fill=INK)
    route_rows = (
        (COPY["route_1"], COPY["route_1_value"], 1.0),
        (COPY["route_2"], COPY["route_2_value"], 0.76),
        (COPY["route_3"], COPY["route_3_value"], 0.66),
    )
    row_y = routes[1] + int(label.size * 2.4)
    row_h = max(44, (routes[3] - row_y - 16) // 3)
    for name, amount, fraction in route_rows:
        draw.text((routes[0] + 24, row_y), name, font=sub, fill=INK)
        amount_w = text_width(draw, amount, label)
        draw.text((routes[2] - 24 - amount_w, row_y), amount, font=label, fill=INK)
        bar_y = row_y + int(sub.size * 1.35)
        bar_w = int((routes[2] - routes[0] - 48) * fraction)
        draw.rounded_rectangle((routes[0] + 24, bar_y, routes[0] + 24 + bar_w, bar_y + 10), radius=5, fill=GOLD)
        row_y += row_h


def bars(draw, chart, values: list[int], labels: list[str]) -> None:
    tick = font("DMSans-Medium.ttf", max(12, (chart[2] - chart[0]) // 42))
    left = chart[0] + 24
    right = chart[2] - 24
    top = chart[1] + int(tick.size * 3.2)
    bottom = chart[3] - int(tick.size * 2.4)
    peak = max(values)
    gap = 10
    span = right - left
    bar_w = (span - gap * (len(values) - 1)) / len(values)
    for index, value in enumerate(values):
        x = left + index * (bar_w + gap)
        height = (bottom - top) * (value / peak)
        color = GOLD if index == len(values) - 1 else NAVY
        draw.rounded_rectangle((x, bottom - height, x + bar_w, bottom), radius=6, fill=color)
        label = labels[index]
        lw = text_width(draw, label, tick)
        draw.text((x + (bar_w - lw) / 2, bottom + 6), label, font=tick, fill=MUTED)


def wrap(draw, text: str, face, x: int, y: int, width: int, fill, gap: int) -> int:
    words = text.split()
    line = ""
    cursor = y
    for word in words:
        trial = word if not line else f"{line} {word}"
        if text_width(draw, trial, face) <= width:
            line = trial
            continue
        draw.text((x, cursor), line, font=face, fill=fill)
        cursor += int(face.size * 1.35) + gap
        line = word
    if line:
        draw.text((x, cursor), line, font=face, fill=fill)
        cursor += int(face.size * 1.35)
    return cursor


def centered_in(draw, text: str, face, box, fill) -> None:
    x0, y0, x1, y1 = box
    tw = text_width(draw, text, face)
    ascent, descent = face.getmetrics()
    th = ascent + descent
    draw.text((x0 + (x1 - x0 - tw) / 2, y0 + (y1 - y0 - th) / 2), text, font=face, fill=fill)


def render_slide(size: tuple[int, int], slide: str):
    from PIL import ImageDraw

    image = gradient(size)
    draw = ImageDraw.Draw(image)
    width, height = size
    title_face = font("DMSans-Bold.ttf", max(54, width // 16))
    sub_face = font("DMSans-Medium.ttf", max(28, width // 32))
    if slide == "06_premium":
        title, subtitle = COPY["premium_title"], COPY["premium_subtitle"]
    else:
        title, subtitle = COPY["analytics_title"], COPY["analytics_subtitle"]
    centered(draw, title, title_face, int(height * 0.045), width, WHITE)
    centered(draw, subtitle, sub_face, int(height * 0.045) + int(title_face.size * 1.25), width, GOLD_SOFT)
    phone_top = int(height * 0.18)
    phone_width = int(width * 0.78)
    phone_left = (width - phone_width) // 2
    phone = (phone_left, phone_top, phone_left + phone_width, height - int(height * 0.028))
    screen = phone_chrome(image, draw, phone, title, subtitle, COPY["premium_badge"])
    if slide == "06_premium":
        draw_premium(image, draw, screen)
    else:
        draw_analytics(image, draw, screen)
    return image


def render() -> int:
    for folder, size in SIZES.items():
        for slide in SLIDES:
            dest = OUT / folder / f"{slide}.png"
            dest.parent.mkdir(parents=True, exist_ok=True)
            image = render_slide(size, slide)
            image.save(dest, "PNG", optimize=True)
            print(f"render {dest.relative_to(ROOT)}  {size[0]}x{size[1]}")
    return check()


def main() -> int:
    if "--check" in sys.argv:
        return check()
    return render()


if __name__ == "__main__":
    sys.exit(main())
