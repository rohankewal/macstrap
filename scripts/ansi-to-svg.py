#!/usr/bin/env python3
"""Render captured terminal output (ANSI SGR sequences and all) to an SVG.

Used to generate the terminal images in the README. The point of rendering a
real capture rather than hand-writing the SVG is that the images can't drift
from what the tools actually print: regenerate with scripts/gen-screenshots.sh
and any change in the output shows up in the diff.

Usage: ansi-to-svg.py <input.raw> <output.svg> --title "macstrap doctor"
"""
import argparse
import html
import re
import sys

# Catppuccin Mocha — Macstrap's default theme, so the images match a fresh install.
BG, HEADER, TEXT, DIM = "#1e1e2e", "#181825", "#cdd6f4", "#6c7086"
ANSI = {31: "#f38ba8", 32: "#a6e3a1", 33: "#f9e2af", 34: "#89b4fa", 35: "#cba6f7", 36: "#94e2d5"}
DOTS = ("#ff5f57", "#febc2e", "#28c840")

FONT = "ui-monospace, SFMono-Regular, 'SF Mono', Menlo, Consolas, monospace"
FS, LH, CW, PAD, HEAD = 13, 20, 7.8, 18, 36

SGR = re.compile(r"\x1b\[([0-9;]*)m")


def parse(raw, cols):
    """-> [[(text, color, bold), ...], ...], one list per (wrapped) line."""
    # `script` echoes the EOF it gets from </dev/null as ^D plus backspaces.
    raw = re.sub(r"^\^D[\x08]*", "", raw.replace("\r\n", "\n").replace("\r", ""))
    raw = raw.replace("\x08", "")
    # Anything left that isn't SGR (cursor moves, title sets) we don't render.
    raw = re.sub(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)", "", raw)
    raw = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", lambda m: m.group(0) if m.group(0).endswith("m") else "", raw)

    out = []
    for line in raw.split("\n"):
        runs, color, bold = [], TEXT, False
        # One capture group means split() alternates: text, code, text, code...
        for i, piece in enumerate(SGR.split(line)):
            if i % 2 == 0:
                if piece:
                    runs.append((piece, color, bold))
                continue
            codes = [int(c) for c in piece.split(";") if c != ""] or [0]
            for code in codes:
                if code == 0:
                    color, bold = TEXT, False
                elif code == 1:
                    bold = True
                elif code == 2:
                    color = DIM
                elif code in ANSI:
                    color = ANSI[code]

        # Tabs carry real layout here — `ls` columnises with them — and SVG has
        # no tab stops, so expand them to 8-column stops like a terminal does.
        expanded, at = [], 0
        for text, color, bold in runs:
            buf = ""
            for ch in text:
                if ch == "\t":
                    pad = 8 - (at % 8)
                    buf += " " * pad
                    at += pad
                else:
                    buf += ch
                    at += 1
            expanded.append((buf, color, bold))
        runs = expanded

        # Wrap the way a terminal `cols` wide would, so long paths stay legible
        # instead of forcing the whole image to scale down to unreadable.
        cur, width = [], 0
        for text, color, bold in runs:
            while text:
                head, text = text[: cols - width], text[cols - width :]
                cur.append((head, color, bold))
                width += len(head)
                if width >= cols and text:
                    out.append(cur)
                    cur, width = [], 0
        out.append(cur)
    return out


def render(lines, title, cols):
    w = int(PAD * 2 + cols * CW)
    h = int(HEAD + PAD * 2 + len(lines) * LH)
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
        f'viewBox="0 0 {w} {h}" font-family="{FONT}" font-size="{FS}">',
        f'<rect width="{w}" height="{h}" rx="10" fill="{BG}"/>',
        f'<path d="M0 10a10 10 0 0 1 10-10h{w - 20}a10 10 0 0 1 10 10v{HEAD - 10}H0z" fill="{HEADER}"/>',
    ]
    for i, c in enumerate(DOTS):
        parts.append(f'<circle cx="{20 + i * 18}" cy="{HEAD / 2}" r="5.5" fill="{c}"/>')
    if title:
        parts.append(
            f'<text x="{w / 2}" y="{HEAD / 2 + 4}" fill="{DIM}" font-size="11.5" '
            f'text-anchor="middle">{html.escape(title)}</text>'
        )

    for row, runs in enumerate(lines):
        y = HEAD + PAD + row * LH
        col = 0
        for text, color, bold in runs:
            if text.strip():
                weight = ' font-weight="bold"' if bold else ""
                # Each run is placed at an absolute column, so a viewer whose
                # monospace font advances at anything other than CW would drift
                # and overlap the next run. textLength pins every run to exactly
                # the width its character count implies, whatever font resolves.
                parts.append(
                    f'<text x="{PAD + col * CW:.1f}" y="{y}" fill="{color}"{weight} '
                    f'textLength="{len(text) * CW:.1f}" lengthAdjust="spacing" '
                    f'xml:space="preserve">{html.escape(text)}</text>'
                )
            col += len(text)
    parts.append("</svg>")
    return "\n".join(parts)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dest")
    ap.add_argument("--title", default="")
    ap.add_argument("--cols", type=int, default=104)
    a = ap.parse_args()

    raw = open(a.src, encoding="utf8", errors="replace").read()
    lines = parse(raw, a.cols)
    while lines and not any(t.strip() for t, _, _ in lines[-1]):
        lines.pop()
    open(a.dest, "w", encoding="utf8").write(render(lines, a.title, a.cols))
    print(f"{a.dest}  ({len(lines)} lines)", file=sys.stderr)


if __name__ == "__main__":
    main()
