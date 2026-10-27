#!/bin/sh
#
# Build the macOS app in Release and install it into /Applications.
#
#   scripts/install-macos.sh            build, then replace /Applications/Claviron.app
#   scripts/install-macos.sh --no-open  do not relaunch the app afterwards
#
# The installed bundle is replaced as a whole, never copied over: files the new
# build no longer ships must not linger. A running copy is quit first and
# reopened afterwards, so the new build is what runs. Signing is the project's
# own (Personal Team or "Sign to Run Locally"); this script does not notarize.

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
derived_data="$repository_dir/build"
app_name="Claviron.app"
built_app="$derived_data/Build/Products/Release/$app_name"
installed_app="/Applications/$app_name"
reopen=true

for argument in "$@"; do
    case "$argument" in
        --no-open) reopen=false ;;
        -h|--help) sed -n '3,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $argument" >&2; exit 2 ;;
    esac
done

xcodebuild \
    -project "$repository_dir/claviron-apple.xcodeproj" \
    -scheme Claviron \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived_data" \
    build

[ -d "$built_app" ] || { echo "build produced no $built_app" >&2; exit 1; }

was_running=false
if pgrep -xq Claviron; then
    was_running=true
    # AppleScript's quit returns once the app has quit; no polling here.
    osascript -e 'tell application "Claviron" to quit'
fi

rm -rf -- "$installed_app"
ditto "$built_app" "$installed_app"
echo "Installed $installed_app"

if $reopen && $was_running; then
    open "$installed_app"
fi
