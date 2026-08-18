#!/bin/bash
# Capture one complete, deterministic Zoji App Store screenshot set.
set -euo pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "usage: $0 <simulator-udid> <zh-Hans|en> [YYYY-MM-DD]" >&2
    exit 2
fi

UDID="$1"
LOCALE="$2"
RUN_DATE="${3:-$(date +%F)}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_ID="com.haoqianglyu.zoji"
RAW_DIR="$ROOT/marketing/screenshots/$RUN_DATE/iphone-6.9/$LOCALE/raw"

case "$LOCALE" in
    zh-Hans)
        APPLE_LANGUAGES="(zh-Hans)"
        APPLE_LOCALE="zh_CN"
        ;;
    en)
        APPLE_LANGUAGES="(en)"
        APPLE_LOCALE="en_US"
        ;;
    *)
        echo "unsupported locale: $LOCALE (expected zh-Hans or en)" >&2
        exit 2
        ;;
esac

mkdir -p "$RAW_DIR"
"$ROOT/scripts/prepare_marketing_simulator.sh" "$UDID"

capture_scene() {
    local filename="$1"
    local route_flag="${2:-}"
    local settle_seconds="${3:-5}"
    local launch_args=(
        -AppleLanguages "$APPLE_LANGUAGES"
        -AppleLocale "$APPLE_LOCALE"
        -zojiMarketingDemo
    )

    if [ -n "$route_flag" ]; then
        launch_args+=("$route_flag")
    fi

    xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID" "${launch_args[@]}"
    sleep "$settle_seconds"
    xcrun simctl io "$UDID" screenshot "$RAW_DIR/$filename"
}

capture_scene "01-home.png"
capture_scene "02-records.png" "-zojiMarketingRecordsScreenshot"
capture_scene "03-reminders.png" "-zojiMarketingRemindersScreenshot"
capture_scene "04-family.png" "-zojiMarketingFamilyScreenshot"
if [ "$LOCALE" = "en" ]; then
    capture_scene "05-hospitals.png" "-zojiMarketingHospitalsUSScreenshot" 12
else
    # The U.S. fixture deliberately contains Seattle map labels and English
    # hospital data. Never use it for the Simplified Chinese storefront.
    capture_scene "05-hospitals.png" "" 12
fi
capture_scene "06-health-record.png" "-zojiMarketingHealthRecordScreenshot" 6

python3 "$ROOT/marketing/cards/make_cards.py" --date "$RUN_DATE" --locales "$LOCALE"
python3 "$ROOT/scripts/verify_marketing_screenshots.py" --date "$RUN_DATE" --locales "$LOCALE"

echo "captured $LOCALE screenshot set in $RAW_DIR"
