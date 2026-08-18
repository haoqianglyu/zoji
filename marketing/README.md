# Zoji App Store marketing pipeline

This folder turns reviewed simulator captures into repeatable, localized App
Store cards. It borrows the useful separation from the supplied Bloom project:

1. raw captures are immutable evidence of what the app rendered;
2. cards are generated marketing artwork and are the files uploaded;
3. shipped runs stay in dated folders instead of being overwritten;
4. machine checks catch missing, duplicated, or wrongly-sized files;
5. `review.html` keeps the final visual decision human.

Zoji now has a deterministic screenshot fixture inspired by the useful part of
Bloom's demo-data flow. It is compiled only in Debug, runs only when launched
with `-zojiMarketingDemo`, stores everything in memory, and disables CloudKit.
The fixture uses fictional pets and records, so marketing captures neither
alter the user's database nor expose personal information.

## Folder layout

```text
marketing/screenshots/<YYYY-MM-DD>/iphone-6.9/<locale>/
  raw/       original 1320 x 2868 PNG captures
  cards/     generated 1320 x 2868 store artwork
```

Supported copy is currently configured for `zh-Hans` and `en` in
`marketing/cards/scenes.json`. Raw screenshots must use the configured scene
names exactly.

## Capture a clean raw screenshot

Use a dedicated iPhone 17 Pro Max simulator whose runtime renders 1320 x 2868.
After booting it, normalize the status bar:

```bash
./scripts/prepare_marketing_simulator.sh <UDID>
```

Build and install the Debug app with the isolated fixture. The complete set can
then be captured without manually navigating each screen:

```bash
./scripts/capture_zoji_marketing_set.sh <UDID> zh-Hans 2026-08-18
./scripts/capture_zoji_marketing_set.sh <UDID> en 2026-08-18
```

The batch routes are deterministic and Debug-only:

| File | Direct route flag |
| --- | --- |
| `01-home.png` | none |
| `02-records.png` | `-zojiMarketingRecordsScreenshot` |
| `03-reminders.png` | `-zojiMarketingRemindersScreenshot` |
| `04-family.png` | `-zojiMarketingFamilyScreenshot` |
| `05-hospitals.png` | `-zojiMarketingHospitalsUSScreenshot` |
| `06-health-record.png` | `-zojiMarketingHealthRecordScreenshot` |

For an individual manual launch:

```bash
xcrun simctl launch <UDID> com.haoqianglyu.zoji \
  -AppleLanguages '(zh-Hans)' -AppleLocale zh_CN -zojiMarketingDemo
```

Append the matching route flag from the table. These routes are compiled only
in Debug builds.

Navigate the app to the intended scene, wait for animations and map tiles to
settle, then capture:

```bash
./scripts/capture_marketing_screenshot.sh <UDID> \
  marketing/screenshots/2026-08-18/iphone-6.9/zh-Hans/raw/01-home.png
```

The final cards use Apple's device bezel, which supplies the product frame and
Dynamic Island artwork. Review the card output rather than judging the raw
framebuffer capture in isolation.

For English, use `-AppleLanguages '(en)' -AppleLocale en_US` and capture into
the `en/raw` folder. The fixture supplies English pet names, records, reminders,
providers, US units, USD, and an accepted fictional family member; translating
only the marketing headline is not enough.

The English hospital route is intentionally different from the Chinese route.
It fixes the camera on Seattle and renders three fictional US hospitals on the
SwiftUI `Map`/Apple MapKit path. It never requests location, performs a live
search, initializes the AMap SDK, or shows the AMap-consent flow. When captures
are made from mainland China, Apple's MapKit tiles may still carry the local
map-data-provider attribution; that attribution comes from Apple MapKit and
must not be covered or altered.

The batch capture script applies `-zojiMarketingHospitalsUSScreenshot` only to
the English locale. The Simplified Chinese storefront must use a Chinese-region
hospital capture; do not reuse the Seattle fixture merely by translating the
surrounding interface.

## Generate and verify cards

```bash
python3 marketing/cards/make_cards.py --date 2026-08-18
python3 scripts/verify_marketing_screenshots.py --date 2026-08-18
open marketing/screenshots/2026-08-18/iphone-6.9/review.html
```

The compositor uses Apple's unmodified iPhone product bezel supplied with the
reference project. If the bezel is replaced, re-measure its screen aperture;
the percentages in `make_cards.py` are asset-specific.

Upload the files from each locale's `cards/` directory, not `raw/`. The first
three screenshots receive the most visibility in App Store surfaces, so the
recommended ordering is Home, Records, and Reminders.

## Human review checklist

- Status bar is 9:41, Wi-Fi/full signal, 100% battery, with no charging bolt.
- No real member name, address, medical document, or other private data.
- No placeholder copy such as `XX`, debug values, duplicate currency symbols,
  clipped pet chips, screenshot-preview overlays, or partially scrolled titles.
- The Chinese and English scenes tell the same story and use the same order.
- Maps have finished loading and do not imply guaranteed medical availability.
- The first three cards remain understandable at thumbnail size.

The initial hand-captured 2026-08-18 set is preserved under `draft-raw/`. The
submission set was recaptured from the isolated marketing fixture with a
normalized status bar and fictional data.
