#!/usr/bin/env python3
"""Build App Store-ready Zoji cards from raw 6.9-inch screenshots.

The compositor deliberately uses only Python's standard library and a local
Chrome installation. It never edits the raw captures. Each rendered card is
archived beside its source run:

  marketing/screenshots/<date>/iphone-6.9/<locale>/raw/01-home.png
  marketing/screenshots/<date>/iphone-6.9/<locale>/cards/01-home.png

Scene names and localized copy live in scenes.json so the layout and copy do
not drift between languages.
"""

from __future__ import annotations

import argparse
import html
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile


HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parent.parent
SCREENSHOT_ROOT = REPO_ROOT / "marketing" / "screenshots"
CONFIG_PATH = HERE / "scenes.json"
BEZEL_PATH = HERE / "assets" / "bezel-iphone-17-pro-max-silver.png"
CHROME_CANDIDATES = [
    Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"),
    Path("/Applications/Chromium.app/Contents/MacOS/Chromium"),
]


def png_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as stream:
        header = stream.read(24)
    if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"not a PNG: {path}")
    return struct.unpack(">II", header[16:24])


def newest_run() -> str:
    runs = sorted(
        path.name
        for path in SCREENSHOT_ROOT.iterdir()
        if path.is_dir() and len(path.name) == 10 and path.name[4] == "-"
    )
    if not runs:
        raise SystemExit("no dated screenshot run exists under marketing/screenshots")
    return runs[-1]


def chrome_path() -> Path:
    for candidate in CHROME_CANDIDATES:
        if candidate.exists():
            return candidate
    raise SystemExit("Google Chrome or Chromium is required to render marketing cards")


def highlighted_line(text: str, highlight: str) -> str:
    escaped = html.escape(text)
    escaped_highlight = html.escape(highlight)
    if not highlight or escaped_highlight not in escaped:
        return escaped
    return escaped.replace(escaped_highlight, f"<em>{escaped_highlight}</em>", 1)


def font_size(line1: str, line2: str, locale: str) -> int:
    longest = max(len(line1), len(line2))
    if locale == "zh-Hans":
        return 78 if longest <= 11 else (70 if longest <= 14 else 62)
    return 72 if longest <= 31 else (64 if longest <= 38 else 57)


def card_html(source: Path, locale: str, caption: dict[str, str]) -> str:
    line1 = highlighted_line(caption["line1"], caption.get("highlight", ""))
    line2 = highlighted_line(caption["line2"], caption.get("highlight", ""))
    size = font_size(caption["line1"], caption["line2"], locale)
    family = (
        "'PingFang SC','Hiragino Sans GB','Helvetica Neue',sans-serif"
        if locale == "zh-Hans"
        else "-apple-system,BlinkMacSystemFont,'Helvetica Neue',sans-serif"
    )
    footer = "宠物生活，认真记录" if locale == "zh-Hans" else "PET LIFE, BEAUTIFULLY KEPT"
    return f"""<!doctype html>
<html><head><meta charset=\"utf-8\"><style>
* {{ box-sizing: border-box; }}
html, body {{ margin: 0; width: 1320px; height: 2868px; overflow: hidden; }}
body {{
  background:
    radial-gradient(circle at 11% 3%, rgba(255,255,255,.92) 0 115px, transparent 116px),
    radial-gradient(circle at 92% 12%, rgba(76,139,130,.10) 0 250px, transparent 251px),
    linear-gradient(160deg, #F4FBF8 0%, #E9F6F1 55%, #E4F2EE 100%);
  color: #182421;
  font-family: {family};
}}
.brand {{ position: absolute; top: 62px; left: 0; right: 0; text-align: center;
  color: #6B8781; font-size: 28px; font-weight: 700; letter-spacing: 8px; }}
.caption {{ height: 470px; padding: 125px 72px 28px; display: flex;
  justify-content: center; align-items: center; text-align: center; }}
.caption h1 {{ margin: 0; font-size: {size}px; line-height: 1.20; font-weight: 760;
  letter-spacing: -1.5px; white-space: nowrap; }}
.caption em {{ color: #347E76; font-style: normal; }}
.device {{ position: relative; width: 1078px; height: 2200px; margin: 8px auto 0; }}
.screen {{ position: absolute; left: 5.102%; top: 2.200%; width: 89.796%; height: 95.600%;
  object-fit: cover; border-radius: 8.6% / 4.2%; }}
.bezel {{ position: absolute; inset: 0; width: 100%; height: 100%; z-index: 2; }}
.foot {{ position: absolute; bottom: 58px; left: 0; right: 0; text-align: center;
  color: rgba(52,126,118,.66); font-size: 24px; font-weight: 650; letter-spacing: 3px; }}
</style></head><body>
<div class=\"brand\">ZOJI</div>
<div class=\"caption\"><h1>{line1}<br>{line2}</h1></div>
<div class=\"device\">
  <img class=\"screen\" src=\"{source.as_uri()}\">
  <img class=\"bezel\" src=\"{BEZEL_PATH.as_uri()}\">
</div>
<div class=\"foot\">{footer}</div>
</body></html>"""


def render_card(chrome: Path, html_path: Path, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        output.unlink()
    command = [
        str(chrome),
        "--headless",
        "--disable-gpu",
        "--hide-scrollbars",
        "--force-device-scale-factor=1",
        "--allow-file-access-from-files",
        "--virtual-time-budget=3000",
        "--window-size=1320,2868",
        f"--screenshot={output}",
        html_path.as_uri(),
    ]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0 or not output.exists():
        message = result.stderr.strip() or "Chrome wrote no screenshot"
        raise RuntimeError(f"render failed for {output.name}: {message}")


def write_review(run_root: Path, locale_outputs: dict[str, list[Path]]) -> None:
    sections = []
    for locale, outputs in locale_outputs.items():
        figures = "\n".join(
            f'<figure><img src="{path.relative_to(run_root).as_posix()}"><figcaption>{html.escape(path.stem)}</figcaption></figure>'
            for path in outputs
        )
        sections.append(f"<h2>{html.escape(locale)}</h2><main>{figures}</main>")
    document = f"""<!doctype html><html><head><meta charset=\"utf-8\"><style>
body{{margin:28px;background:#15201d;color:#edf7f3;font:16px -apple-system,sans-serif}}
h1{{margin-bottom:4px}} h2{{margin-top:34px}}
main{{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:18px}}
figure{{margin:0}} img{{width:100%;display:block;border-radius:14px;box-shadow:0 12px 30px #0007}}
figcaption{{padding:8px 2px;color:#a9c2bb}}
</style></head><body><h1>Zoji App Store cards</h1>{''.join(sections)}</body></html>"""
    (run_root / "review.html").write_text(document, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--date", default=None, help="capture run date; defaults to newest")
    parser.add_argument("--locales", nargs="*", help="locales to render; defaults to raw folders present")
    args = parser.parse_args()

    run_date = args.date or newest_run()
    run_root = SCREENSHOT_ROOT / run_date / "iphone-6.9"
    if not run_root.exists():
        raise SystemExit(f"missing run: {run_root}")
    if not BEZEL_PATH.exists():
        raise SystemExit(f"missing Apple product bezel: {BEZEL_PATH}")

    config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    expected = (config["device"]["width"], config["device"]["height"])
    available = sorted(path.name for path in run_root.iterdir() if (path / "raw").is_dir())
    locales = args.locales or available
    if not locales:
        raise SystemExit(f"no locale raw folders found under {run_root}")

    chrome = chrome_path()
    locale_outputs: dict[str, list[Path]] = {}
    with tempfile.TemporaryDirectory(prefix="zoji-cards-") as temporary:
        temporary_root = Path(temporary)
        for locale in locales:
            raw_dir = run_root / locale / "raw"
            cards_dir = run_root / locale / "cards"
            if not raw_dir.is_dir():
                raise SystemExit(f"missing raw folder for {locale}: {raw_dir}")
            outputs: list[Path] = []
            for scene in config["scenes"]:
                caption = scene["captions"].get(locale)
                if caption is None:
                    raise SystemExit(f"{scene['id']} has no caption for locale {locale}")
                source = raw_dir / scene["source"]
                if not source.exists():
                    raise SystemExit(f"missing source: {source}")
                actual = png_size(source)
                if actual != expected:
                    raise SystemExit(f"wrong source size {actual} for {source}; expected {expected}")
                html_path = temporary_root / f"{locale}-{scene['id']}.html"
                html_path.write_text(card_html(source, locale, caption), encoding="utf-8")
                output = cards_dir / scene["source"]
                render_card(chrome, html_path, output)
                if png_size(output) != expected:
                    raise SystemExit(f"Chrome rendered the wrong dimensions for {output}")
                outputs.append(output)
                print(f"{locale}: {scene['id']} -> {output.relative_to(REPO_ROOT)}")
            locale_outputs[locale] = outputs

    write_review(run_root, locale_outputs)
    print(f"review -> {(run_root / 'review.html').relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
