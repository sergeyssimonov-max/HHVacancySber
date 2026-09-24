#!/bin/bash
# Build СберВакансии from a clean commit and package it as a DMG.
#
#   scripts/release.sh --output-dir <directory>
#
# Signing is ad hoc by default. For distribution outside this Mac set
#   DEVELOPER_ID="Developer ID Application: Name (TEAMID)"   sign app and DMG with Developer ID
#   NOTARY_PROFILE=<profile>   also notarize and staple (xcrun notarytool store-credentials <profile>)
set -euo pipefail

usage() { echo "Usage: scripts/release.sh --output-dir <directory>"; }
fail() { echo "release: $*" >&2; exit 1; }

output_dir=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      [[ $# -ge 2 && -n "$2" ]] || { usage >&2; exit 2; }
      output_dir="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
[[ -n "$output_dir" ]] || { usage >&2; exit 2; }
[[ -z "${NOTARY_PROFILE:-}" || -n "${DEVELOPER_ID:-}" ]] || fail "NOTARY_PROFILE requires DEVELOPER_ID"

root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$root"
[[ -z "$(git status --porcelain)" ]] || fail "working tree is not clean; commit or stash first"
commit="$(git rev-parse HEAD)"

mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd -P)"
work="$(mktemp -d "${TMPDIR:-/tmp}/hhvacancysber-release.XXXXXX")"
trap 'rm -rf "$work"' EXIT

# Same strict settings as the CI release-build job.
xcodebuild -quiet \
  -project HHVacancySber/HHVacancySber.xcodeproj -scheme HHVacancySber \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$work/DerivedData" \
  SWIFT_STRICT_CONCURRENCY=complete SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES \
  build
app="$work/DerivedData/Build/Products/Release/СберВакансии.app"
[[ -d "$app" ]] || fail "expected $app"

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  codesign --force --options runtime --timestamp \
    --entitlements HHVacancySber/HHVacancySber/HHVacancySber.entitlements \
    --sign "$DEVELOPER_ID" "$app"
fi
# Valid signature, sandbox and network/file entitlements, no get-task-allow.
python3 scripts/verify_release_entitlements.py --app "$app" > "$work/entitlements.json" \
  || { cat "$work/entitlements.json" >&2; fail "entitlement check failed"; }
signature="$(codesign -d --verbose=2 "$app" 2>&1)"
[[ "$signature" == *"flags="*"runtime"* ]] || fail "hardened runtime is not enabled"

plist="$app/Contents/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
name="HHVacancySber_${version}_${build}_macos13_arm64.dmg"
[[ ! -e "$output_dir/$name" ]] || fail "$output_dir/$name already exists"

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  signing="Сборка подписана Developer ID."
  [[ -z "${NOTARY_PROFILE:-}" ]] || signing="Сборка подписана Developer ID и нотаризована Apple."
else
  signing="Сборка подписана ad hoc и не нотаризована Apple: при первом запуске macOS покажет
предупреждение. Открыть приложение можно в «Системные настройки – Конфиденциальность и безопасность»."
fi

stage="$work/dmg"
mkdir "$stage"
ditto "$app" "$stage/СберВакансии.app"
ln -s /Applications "$stage/Applications"
cat > "$stage/README.txt" <<EOF
СберВакансии $version ($build)

Настольное приложение для macOS: полная выгрузка вакансий работодателей группы Сбера
с hh.ru, избранное и экспорт в PDF. Не является официальным продуктом Сбера или HeadHunter.

Установка: перетащите «СберВакансии» на значок «Программы» и запустите из «Программ».
Требования: macOS 13 или новее, Mac с Apple silicon, подключение к интернету.
Избранное и настройки хранятся только на этом Mac.

$signing

Исходный commit: $commit
EOF

hdiutil create -quiet -volname "СберВакансии" -fs HFS+ -format UDZO -srcfolder "$stage" "$work/$name"
if [[ -n "${DEVELOPER_ID:-}" ]]; then
  codesign --timestamp --sign "$DEVELOPER_ID" "$work/$name"
fi
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$work/$name" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$work/$name"
fi
hdiutil verify -quiet "$work/$name"

mv -n "$work/$name" "$output_dir/$name"
if [[ -e "$work/$name" ]]; then fail "$output_dir/$name appeared during the build"; fi
(cd "$output_dir" && shasum -a 256 "$name" > "$name.sha256")
echo "$output_dir/$name"
