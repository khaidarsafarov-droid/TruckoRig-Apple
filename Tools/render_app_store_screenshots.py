#!/usr/bin/env python3
"""Render App Store phone frames for the listing.

Frames, in order: journal, load detail with chips, weekly goal, gallery,
maintenance, premium, analytics. Same Midnight & Gold plate as the Android
listing. Sizes are the App Store 6.9-inch and 6.5-inch slots. Copy is demo
data only: no real names, phones, or addresses. PNG is RGB, no alpha.

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
    "ipad-13": (2064, 2752),
}

SLIDES = (
    "01_journal",
    "02_load",
    "03_goal",
    "04_gallery",
    "05_maintenance",
    "06_premium",
    "07_analytics",
)

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
    "route_1": "Aurora, CO  to  Arlington, WA",
    "route_1_value": "$3,815.90",
    "route_2": "Kansas City, MO  to  Phoenix, AZ",
    "route_2_value": "$2,890.00",
    "route_3": "Garner, NC  to  Dallas, TX",
    "route_3_value": "$2,500.00",
    "journal_title": "Every load, one list",
    "journal_subtitle": "Search a trip, a city, or a day",
    "load_title": "Finish the load in one tap",
    "load_subtitle": "Miles, deadhead, delivery, dispute",
    "goal_title": "The week, day by day",
    "goal_subtitle": "Booked loads stay in the plan",
    "gallery_title": "Photos stay with the load",
    "gallery_subtitle": "Grouped by trip, ready to share",
    "maint_title": "Service before it is late",
    "maint_subtitle": "Reminders by date and by miles",
    "brand": "TruckoRig",
    "greeting": "Good morning",
    "privacy": "On this device",
    "week_chip": "Week 44  ·  Oct 25 – Oct 31",
    "week_gross": "$4,214",
    "week_goal": "of $7,000 goal",
    "chip_all": "All",
    "chip_today": "Today",
    "chip_week": "This week",
    "chip_day": "Day",
    "trip_1": "#T-DEMO1001",
    "trip_2": "#T-DEMO1002",
    "trip_3": "#T-DEMO1003",
    "route_a": "Atlanta, GA  to  Carlisle, PA",
    "route_b": "Dallas, TX  to  Chicago, IL",
    "route_c": "Denver, CO  to  Kansas City, MO",
    "rate_a": "$2,111.72",
    "rate_b": "$1,359.00",
    "rate_c": "$743.00",
    "date_a": "Thu, Oct 29",
    "date_b": "Tue, Oct 27",
    "date_c": "Mon, Oct 26",
    "miles_chip": "Miles · 714 mi",
    "deadhead_chip": "Deadhead 45 mi",
    "delivered_chip": "Delivered",
    "dispute_chip": "Dispute open",
    "stops": "Stops",
    "stop_pu": "ATL2  ·  Atlanta, GA  ·  pickup 6:30 AM",
    "stop_del": "ABE8  ·  Carlisle, PA  ·  delivery Oct 30",
    "goal_heading": "Weekly goal",
    "goal_needed": "Needed  $696.50 / day",
    "planned": "planned",
    "gallery_heading": "Gallery",
    "photos_tab": "Photos",
    "scans_tab": "Scans",
    "filter_load": "By load",
    "photo_count": "4 photos",
    "scan_count": "2 scans",
    "maint_heading": "Maintenance",
    "oil": "Oil change",
    "oil_due": "Due Nov 15  ·  or 5,000 mi",
    "tires": "Tires",
    "tires_due": "Due in 12,400 mi",
    "brakes": "Brake inspection",
    "brakes_due": "Due Dec 2",
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


def png_info(path: Path) -> tuple[int, int, int]:
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path} is not a PNG")
    length, kind = struct.unpack(">I4s", data[8:16])
    if kind != b"IHDR" or length < 13:
        raise SystemExit(f"{path} has no IHDR")
    width, height, _bit_depth, color_type = struct.unpack(">IIBB", data[16:26])
    return width, height, color_type


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
            actual_w, actual_h, color_type = png_info(path)
            if (actual_w, actual_h) != (width, height):
                problems.append(
                    f"{path.relative_to(ROOT)} is {actual_w}x{actual_h}, expected {width}x{height}"
                )
            # 4 = grayscale+alpha, 6 = RGB+alpha. App Store rejects an alpha channel.
            if color_type in (4, 6):
                problems.append(f"{path.relative_to(ROOT)} has an alpha channel")
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


def phone_chrome(base, draw, box, title: str, subtitle: str, badge: str, pad: bool = False) -> tuple[int, int, int, int]:
    """Draws the device and returns the screen content box (x, y, right, bottom)."""
    x0, y0, x1, y1 = box
    bezel = max(18, (x1 - x0) // 36) if pad else max(12, (x1 - x0) // 48)
    rounded(draw, box, (x1 - x0) // 14 if pad else (x1 - x0) // 8, (22, 25, 41))
    screen = (x0 + bezel, y0 + bezel, x1 - bezel, y1 - bezel)
    rounded(draw, screen, (x1 - x0) // 18 if pad else (x1 - x0) // 10, PAGE)
    sx0, sy0, sx1, sy1 = screen
    width = sx1 - sx0
    if pad:
        cx = (sx0 + sx1) / 2
        draw.ellipse((cx - 7, sy0 + 16, cx + 7, sy0 + 30), fill=(11, 13, 28))
    else:
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


CAPTIONS = {
    "01_journal": ("journal_title", "journal_subtitle"),
    "02_load": ("load_title", "load_subtitle"),
    "03_goal": ("goal_title", "goal_subtitle"),
    "04_gallery": ("gallery_title", "gallery_subtitle"),
    "05_maintenance": ("maint_title", "maint_subtitle"),
    "06_premium": ("premium_title", "premium_subtitle"),
    "07_analytics": ("analytics_title", "analytics_subtitle"),
}

SUCCESS = (36, 120, 78)
DANGER = (168, 58, 58)
SUCCESS_BG = (226, 242, 230)
DANGER_BG = (250, 228, 226)


def chip_row(draw, x: int, y: int, items: list[tuple[str, tuple, tuple]], face, height: int, gap: int, right: int) -> int:
    cursor = x
    row = y
    for text, fill, ink in items:
        width = text_width(draw, text, face) + 28
        if cursor + width > right and cursor > x:
            cursor = x
            row += height + gap
        box = (cursor, row, cursor + width, row + height)
        rounded(draw, box, height // 2, fill)
        centered_in(draw, text, face, box, ink)
        cursor += width + gap
    return row + height


def screen_heading(draw, screen, title: str, y: int) -> int:
    sx0, _, sx1, _ = screen
    pad = (sx1 - sx0) // 18
    face = font("DMSans-Bold.ttf", max(26, (sx1 - sx0) // 16))
    draw.text((sx0 + pad, y), title, font=face, fill=INK)
    return y + int(face.size * 1.6)


def draw_journal(image, draw, screen) -> None:
    sx0, sy0, sx1, sy1 = screen
    width = sx1 - sx0
    pad = width // 18
    small = font("Roboto-Regular.ttf", max(16, width // 32))
    medium = font("DMSans-Medium.ttf", max(16, width // 30))
    big = font("DMSans-Bold.ttf", max(32, width // 14))
    y = sy0 + 4
    draw.text((sx0 + pad, y), COPY["brand"], font=big, fill=INK)
    y += int(big.size * 1.35)
    draw.text((sx0 + pad, y), COPY["greeting"], font=small, fill=MUTED)
    y += int(small.size * 2.1)
    badge = (sx0 + pad, y, sx0 + pad + text_width(draw, COPY["privacy"], small) + 36, y + int(small.size * 2.1))
    rounded(draw, badge, 16, (232, 231, 226))
    centered_in(draw, COPY["privacy"], small, badge, MUTED)
    y = badge[3] + 16
    hero_h = int(width * 0.46)
    hero = (sx0 + pad, y, sx1 - pad, y + hero_h)
    rounded(draw, hero, 28, HERO)
    draw.text((hero[0] + 24, hero[1] + 20), COPY["week_chip"], font=small, fill=GOLD_SOFT)
    draw.text((hero[0] + 24, hero[1] + 20 + int(small.size * 2)), COPY["week_gross"], font=big, fill=WHITE)
    draw.text((hero[0] + 24, hero[1] + 20 + int(small.size * 2) + int(big.size * 1.2)), COPY["week_goal"], font=small, fill=GOLD_SOFT)
    stats = (("RPM", "$2.95"), ("Miles", "2,140"), ("Loads", "3"))
    stat_y = hero[3] - int(small.size * 3.2)
    col = (hero[2] - hero[0] - 48) / 3
    for index, (name, amount) in enumerate(stats):
        sx = hero[0] + 24 + col * index
        draw.text((sx, stat_y), name, font=small, fill=GOLD_SOFT)
        draw.text((sx, stat_y + int(small.size * 1.4)), amount, font=medium, fill=WHITE)
    y = hero[3] + 16
    y = chip_row(
        draw, sx0 + pad, y,
        [
            (COPY["chip_all"], NAVY, WHITE),
            (COPY["chip_today"], (232, 231, 226), INK),
            (COPY["chip_week"], (232, 231, 226), INK),
            (COPY["chip_day"], (232, 231, 226), INK),
        ],
        medium, int(medium.size * 2.2), 8, sx1 - pad,
    ) + 16
    cards = (
        (COPY["date_a"], COPY["trip_1"], COPY["route_a"], COPY["rate_a"]),
        (COPY["date_b"], COPY["trip_2"], COPY["route_b"], COPY["rate_b"]),
        (COPY["date_c"], COPY["trip_3"], COPY["route_c"], COPY["rate_c"]),
    )
    remaining = sy1 - y - 8
    card_h = max(90, remaining // 3 - 10)
    for date, trip, route, rate in cards:
        box = (sx0 + pad, y, sx1 - pad, y + card_h)
        rounded(draw, box, 22, HERO)
        band_h = int(card_h * 0.34)
        bottom = (box[0], box[1] + band_h, box[2], box[3])
        rounded(draw, bottom, 22, CARD)
        draw.rectangle((box[0], box[1] + band_h, box[2], box[1] + band_h + 22), fill=CARD)
        draw.text((box[0] + 18, box[1] + 10), f"{date}  ·  {trip}", font=small, fill=WHITE)
        draw.text((box[0] + 18, box[1] + band_h + 12), route, font=medium, fill=INK)
        draw.text((box[0] + 18, box[1] + band_h + 12 + int(medium.size * 1.4)), rate, font=medium, fill=MUTED)
        y += card_h + 10


def draw_load(image, draw, screen) -> None:
    sx0, sy0, sx1, _sy1 = screen
    width = sx1 - sx0
    pad = width // 18
    small = font("Roboto-Regular.ttf", max(16, width // 32))
    medium = font("DMSans-Medium.ttf", max(18, width // 28))
    big = font("DMSans-Bold.ttf", max(30, width // 15))
    y = screen_heading(draw, screen, COPY["trip_1"], sy0 + 4)
    draw.text((sx0 + pad, y), COPY["date_a"], font=small, fill=MUTED)
    y += int(small.size * 2)
    chip_h = int(small.size * 2.3)
    card_bottom = y + 22 + int(medium.size * 1.8) + int(big.size * 1.6) + chip_h * 2 + 48
    card = (sx0 + pad, y, sx1 - pad, card_bottom)
    rounded(draw, card, 28, CARD)
    draw.text((card[0] + 24, card[1] + 22), COPY["route_a"], font=medium, fill=INK)
    draw.text((card[0] + 24, card[1] + 22 + int(medium.size * 1.8)), COPY["rate_a"], font=big, fill=INK)
    chip_y = card[1] + 22 + int(medium.size * 1.8) + int(big.size * 1.5)
    chip_row(
        draw, card[0] + 24, chip_y,
        [
            (COPY["miles_chip"], (232, 231, 226), INK),
            (COPY["deadhead_chip"], (232, 231, 226), INK),
            (COPY["delivered_chip"], SUCCESS_BG, SUCCESS),
            (COPY["dispute_chip"], DANGER_BG, DANGER),
        ],
        small, chip_h, 8, card[2] - 24,
    )
    y = card[3] + 18
    stops = (sx0 + pad, y, sx1 - pad, y + int(width * 0.48))
    rounded(draw, stops, 28, CARD)
    draw.text((stops[0] + 24, stops[1] + 20), COPY["stops"], font=medium, fill=INK)
    draw.text((stops[0] + 24, stops[1] + 20 + int(medium.size * 2)), COPY["stop_pu"], font=small, fill=INK)
    draw.text((stops[0] + 24, stops[1] + 20 + int(medium.size * 2) + int(small.size * 2.2)), COPY["stop_del"], font=small, fill=INK)


def draw_goal(image, draw, screen) -> None:
    sx0, sy0, sx1, sy1 = screen
    width = sx1 - sx0
    pad = width // 18
    small = font("Roboto-Regular.ttf", max(16, width // 32))
    medium = font("DMSans-Medium.ttf", max(16, width // 30))
    big = font("DMSans-Bold.ttf", max(32, width // 14))
    y = screen_heading(draw, screen, COPY["goal_heading"], sy0 + 4)
    hero = (sx0 + pad, y, sx1 - pad, y + int(width * 0.38))
    rounded(draw, hero, 28, HERO)
    draw.text((hero[0] + 24, hero[1] + 22), COPY["week_chip"], font=small, fill=GOLD_SOFT)
    draw.text((hero[0] + 24, hero[1] + 22 + int(small.size * 2)), COPY["week_gross"], font=big, fill=WHITE)
    draw.text((hero[0] + 24, hero[1] + 22 + int(small.size * 2) + int(big.size * 1.15)), COPY["week_goal"], font=small, fill=GOLD_SOFT)
    y = hero[3] + 16
    draw.text((sx0 + pad, y), COPY["goal_needed"], font=medium, fill=INK)
    y += int(medium.size * 2.2)
    days = (
        ("Mon", "$743.00", ""),
        ("Tue", "$1,359.00", ""),
        ("Wed", "$0", ""),
        ("Thu", "$2,111.72", COPY["planned"]),
        ("Fri", "$0", ""),
        ("Sat", "$0", ""),
        ("Sun", "$0", ""),
    )
    remaining = sy1 - y - 8
    row_h = max(36, remaining // len(days) - 6)
    for name, amount, note in days:
        box = (sx0 + pad, y, sx1 - pad, y + row_h)
        rounded(draw, box, 14, CARD)
        draw.text((box[0] + 16, box[1] + (row_h - small.size) / 2), name, font=medium, fill=INK)
        extra = f"  {note}" if note else ""
        label = amount + extra
        lw = text_width(draw, label, small)
        draw.text((box[2] - 16 - lw, box[1] + (row_h - small.size) / 2), label, font=small, fill=MUTED if note else INK)
        y += row_h + 6


def draw_gallery(image, draw, screen) -> None:
    sx0, sy0, sx1, sy1 = screen
    width = sx1 - sx0
    pad = width // 18
    small = font("Roboto-Regular.ttf", max(16, width // 32))
    medium = font("DMSans-Medium.ttf", max(16, width // 30))
    y = screen_heading(draw, screen, COPY["gallery_heading"], sy0 + 4)
    tab_w = (sx1 - sx0 - pad * 2) // 2
    photos = (sx0 + pad, y, sx0 + pad + tab_w - 6, y + int(medium.size * 2.4))
    scans = (photos[2] + 12, y, sx1 - pad, y + int(medium.size * 2.4))
    rounded(draw, photos, 16, NAVY)
    rounded(draw, scans, 16, (232, 231, 226))
    centered_in(draw, COPY["photos_tab"], medium, photos, WHITE)
    centered_in(draw, COPY["scans_tab"], medium, scans, INK)
    y = photos[3] + 14
    y = chip_row(
        draw, sx0 + pad, y,
        [
            (COPY["chip_all"], NAVY, WHITE),
            (COPY["chip_today"], (232, 231, 226), INK),
            (COPY["chip_week"], (232, 231, 226), INK),
            (COPY["filter_load"], (232, 231, 226), INK),
        ],
        small, int(small.size * 2.2), 8, sx1 - pad,
    ) + 16
    cards = (
        (COPY["trip_1"], COPY["route_a"], COPY["date_a"], COPY["photo_count"]),
        (COPY["trip_2"], COPY["route_b"], COPY["date_b"], COPY["scan_count"]),
    )
    remaining = sy1 - y - 8
    card_h = max(140, remaining // 2 - 12)
    swatches = ((196, 168, 120), (120, 146, 176), (168, 176, 150), (176, 140, 140))
    for trip, route, date, count in cards:
        box = (sx0 + pad, y, sx1 - pad, y + card_h)
        rounded(draw, box, 22, CARD)
        draw.text((box[0] + 18, box[1] + 16), trip, font=medium, fill=INK)
        draw.text((box[0] + 18, box[1] + 16 + int(medium.size * 1.45)), route, font=small, fill=INK)
        draw.text((box[0] + 18, box[1] + 16 + int(medium.size * 1.45) + int(small.size * 1.6)), f"{date}  ·  {count}", font=small, fill=MUTED)
        span = box[2] - box[0] - 36
        thumb = (span - 8 * (len(swatches) - 1)) // len(swatches)
        thumb_y = box[3] - thumb - 16
        tx = box[0] + 18
        for color in swatches:
            rounded(draw, (tx, thumb_y, tx + thumb, thumb_y + thumb), 10, color)
            tx += thumb + 8
        y += card_h + 12


def draw_maintenance(image, draw, screen) -> None:
    sx0, sy0, sx1, _sy1 = screen
    width = sx1 - sx0
    pad = width // 18
    small = font("Roboto-Regular.ttf", max(16, width // 32))
    medium = font("DMSans-Medium.ttf", max(18, width // 28))
    y = screen_heading(draw, screen, COPY["maint_heading"], sy0 + 4)
    rows = (
        (COPY["oil"], COPY["oil_due"], DANGER),
        (COPY["tires"], COPY["tires_due"], GOLD_DEEP),
        (COPY["brakes"], COPY["brakes_due"], SUCCESS),
    )
    card_h = int(medium.size * 1.6 + small.size * 2.4 + 40)
    for title, due, dot in rows:
        box = (sx0 + pad, y, sx1 - pad, y + card_h)
        rounded(draw, box, 22, CARD)
        draw.ellipse((box[0] + 22, box[1] + 24, box[0] + 40, box[1] + 42), fill=dot)
        draw.text((box[0] + 56, box[1] + 18), title, font=medium, fill=INK)
        draw.text((box[0] + 56, box[1] + 18 + int(medium.size * 1.6)), due, font=small, fill=MUTED)
        y += card_h + 14


def render_slide(size: tuple[int, int], slide: str):
    from PIL import ImageDraw

    image = gradient(size)
    draw = ImageDraw.Draw(image)
    width, height = size
    is_pad = width / height > 0.7
    title_face = font("DMSans-Bold.ttf", 72 if is_pad else max(54, width // 16))
    sub_face = font("DMSans-Medium.ttf", 36 if is_pad else max(28, width // 32))
    title_key, subtitle_key = CAPTIONS[slide]
    centered(draw, COPY[title_key], title_face, int(height * 0.045), width, WHITE)
    centered(draw, COPY[subtitle_key], sub_face, int(height * 0.045) + int(title_face.size * 1.25), width, GOLD_SOFT)
    phone_top = int(height * (0.14 if is_pad else 0.18))
    phone_width = int(width * (0.9 if is_pad else 0.78))
    phone_left = (width - phone_width) // 2
    phone = (phone_left, phone_top, phone_left + phone_width, height - int(height * 0.028))
    screen = phone_chrome(
        image, draw, phone, COPY[title_key], COPY[subtitle_key], COPY["premium_badge"], pad=is_pad
    )
    drawers = {
        "01_journal": draw_journal,
        "02_load": draw_load,
        "03_goal": draw_goal,
        "04_gallery": draw_gallery,
        "05_maintenance": draw_maintenance,
        "06_premium": draw_premium,
        "07_analytics": draw_analytics,
    }
    drawers[slide](image, draw, screen)
    if image.mode != "RGB":
        image = image.convert("RGB")
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
