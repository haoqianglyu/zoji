#!/usr/bin/env python3
"""Verify the structural guarantees of a Zoji screenshot run.

This intentionally does not claim to judge copy, privacy, animation state, or
visual composition. Those remain a human review in review.html.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys


ROOT = Path(__file__).resolve().parent.parent
SCREENSHOT_ROOT = ROOT / "marketing" / "screenshots"
CONFIG = ROOT / "marketing" / "cards" / "scenes.json"
EXPECTED_SIZE = (1320, 2868)


def png_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as stream:
        header = stream.read(24)
    if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    return struct.unpack(">II", header[16:24])


def digest(path: Path) -> str:
    sha = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            sha.update(block)
    return sha.hexdigest()


def newest_run() -> str:
    candidates = sorted(path.name for path in SCREENSHOT_ROOT.iterdir() if path.is_dir())
    if not candidates:
        raise SystemExit("no screenshot runs found")
    return candidates[-1]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--date", default=None)
    parser.add_argument("--locales", nargs="*")
    args = parser.parse_args()

    date = args.date or newest_run()
    run_root = SCREENSHOT_ROOT / date / "iphone-6.9"
    scenes = json.loads(CONFIG.read_text(encoding="utf-8"))["scenes"]
    locales = args.locales or sorted(path.name for path in run_root.iterdir() if path.is_dir())
    failures: list[str] = []

    for locale in locales:
        seen_raw: dict[str, str] = {}
        seen_cards: dict[str, str] = {}
        for scene in scenes:
            name = scene["source"]
            raw = run_root / locale / "raw" / name
            card = run_root / locale / "cards" / name
            for kind, path in (("raw", raw), ("card", card)):
                if not path.exists():
                    failures.append(f"{locale}/{kind}/{name}: missing")
                    continue
                try:
                    size = png_size(path)
                except ValueError as error:
                    failures.append(f"{locale}/{kind}/{name}: {error}")
                    continue
                if size != EXPECTED_SIZE:
                    failures.append(f"{locale}/{kind}/{name}: {size}, expected {EXPECTED_SIZE}")
            if raw.exists() and card.exists():
                raw_hash = digest(raw)
                card_hash = digest(card)
                if raw_hash == card_hash:
                    failures.append(f"{locale}/{name}: card is byte-identical to raw capture")
                if raw_hash in seen_raw:
                    failures.append(f"{locale}/{name}: duplicates raw {seen_raw[raw_hash]}")
                if card_hash in seen_cards:
                    failures.append(f"{locale}/{name}: duplicates card {seen_cards[card_hash]}")
                seen_raw[raw_hash] = name
                seen_cards[card_hash] = name

    if not (run_root / "review.html").exists():
        failures.append("review.html: missing; run make_cards.py")
    if failures:
        print("marketing screenshot verification failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1
    print(f"verified {len(locales)} locale(s), {len(scenes)} scene(s) each at {EXPECTED_SIZE[0]}x{EXPECTED_SIZE[1]}")
    print("human review still required: copy, privacy, crop, status bar, and App Store ordering")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
