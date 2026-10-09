#!/usr/bin/env python3
"""Generates the BLAKE2b Miner logo, docs/images/logo.svg: a Mac display with an
orange block (a blockchain block) on its screen, struck by a hammer.

It is the source of the app icon: scripts/make-icon.swift renders it at every icon
size. Laid out on the macOS icon grid: a 1024 px canvas with an 824 px rounded square.

Run: python3 gen_logo.py > ../docs/images/logo.svg
"""
import math

S = 1024
INSET, RADIUS = 100, 185

ORANGE_TOP, ORANGE, ORANGE_DARK = "#ffb347", "#f7931a", "#c96a0a"


def cube(cx, cy, r):
    """An isometric block centered at (cx, cy); r is the center-to-corner distance."""
    h = r * math.sqrt(3) / 2
    p = {"t": (cx, cy - r), "ul": (cx - h, cy - r / 2), "ur": (cx + h, cy - r / 2), "c": (cx, cy),
         "ll": (cx - h, cy + r / 2), "lr": (cx + h, cy + r / 2), "b": (cx, cy + r)}
    def face(names, fill):
        return '<polygon points="%s" fill="%s"/>' % (" ".join("%.1f,%.1f" % p[n] for n in names), fill)
    return face(["t", "ur", "c", "ul"], ORANGE_TOP) + face(["ul", "c", "b", "ll"], ORANGE) + face(["c", "ur", "lr", "b"], ORANGE_DARK)


def hammer(contact, angle, size):
    """A hammer whose head's striking face touches `contact`, rotated by `angle`
    degrees: head on top, handle running down to the right."""
    w, h = size * 1.15, size * 0.42    # head
    hl, hw = size * 1.9, size * 0.17   # handle
    a = math.radians(angle)
    fx, fy = -w / 2, -h / 2            # the striking face, in the hammer's own coordinates
    tx = contact[0] - (fx * math.cos(a) - fy * math.sin(a))
    ty = contact[1] - (fx * math.sin(a) + fy * math.cos(a))
    return f'''<g transform="translate({tx:.1f},{ty:.1f}) rotate({angle})" filter="url(#shadow)">
  <rect x="{-hw / 2:.1f}" y="{-h * 0.2:.1f}" width="{hw:.1f}" height="{hl:.1f}" rx="{hw / 2:.1f}" fill="url(#wood)" stroke="#5a3210" stroke-width="6"/>
  <rect x="{-w / 2:.1f}" y="{-h:.1f}" width="{w:.1f}" height="{h:.1f}" rx="{h * 0.18:.1f}" fill="url(#steel)" stroke="#2b2f36" stroke-width="7"/>
  <rect x="{-w / 2 + 12:.1f}" y="{-h + 10:.1f}" width="{w - 24:.1f}" height="{h * 0.22:.1f}" rx="8" fill="#fff" opacity="0.35"/>
</g>'''


def sparks(x, y, scale):
    """Sparks flying up and to the left from the impact at (x, y)."""
    lines = []
    for angle, length in ((-175, 70), (-150, 100), (-125, 80), (-100, 95)):
        a = math.radians(angle)
        r1, r2 = 34 * scale, (34 + length) * scale
        lines.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#ffd36b" stroke-width="%.1f" stroke-linecap="round"/>'
                     % (x + r1 * math.cos(a), y + r1 * math.sin(a), x + r2 * math.cos(a), y + r2 * math.sin(a), 16 * scale))
    return "\n".join(lines)


def logo():
    dx, dy, dw, dh = 200, 250, 624, 420   # the display
    block_x, block_y = S / 2 - 30, dy + dh / 2 + 30
    impact = (S / 2 - 12, dy + dh / 2 - 44)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">
<defs>
  <linearGradient id="background" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{ORANGE_TOP}"/><stop offset="1" stop-color="#e2700c"/></linearGradient>
  <linearGradient id="screen" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2b2f36"/><stop offset="1" stop-color="#101216"/></linearGradient>
  <linearGradient id="steel" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#e8edf2"/><stop offset="1" stop-color="#8d98a5"/></linearGradient>
  <linearGradient id="wood" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#c98a4b"/><stop offset="1" stop-color="#8a5523"/></linearGradient>
  <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
    <feDropShadow dx="0" dy="10" stdDeviation="14" flood-color="#000" flood-opacity="0.35"/>
  </filter>
</defs>
<rect x="{INSET}" y="{INSET}" width="{S - 2 * INSET}" height="{S - 2 * INSET}" rx="{RADIUS}" fill="url(#background)"/>
<g filter="url(#shadow)">
  <rect x="{dx}" y="{dy}" width="{dw}" height="{dh}" rx="34" fill="#d9dee4"/>
  <rect x="{dx + 26}" y="{dy + 26}" width="{dw - 52}" height="{dh - 52}" rx="14" fill="url(#screen)"/>
  <path d="M{S / 2 - 70},{dy + dh} L{S / 2 + 70},{dy + dh} L{S / 2 + 95},{dy + dh + 110} L{S / 2 - 95},{dy + dh + 110} Z" fill="#b8bfc8"/>
  <rect x="{S / 2 - 150}" y="{dy + dh + 100}" width="300" height="26" rx="13" fill="#9aa3ad"/>
</g>
{cube(block_x, block_y, 120)}
{hammer(impact, -45, 130)}
{sparks(*impact, 0.7)}
</svg>'''


if __name__ == "__main__":
    print(logo())
