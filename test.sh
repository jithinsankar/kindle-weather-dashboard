#!/bin/sh
# ============================================================================
#  Offline tests for weather.sh. No network, no device, POSIX shell only.
#
#      sh test.sh
#
#  Everything here is deterministic. The live-API check is opt-in:
#
#      WEATHER_LIVE=1 sh test.sh
#
#  The first section matters most: it proves the module is actually standalone
#  rather than a file that happens to live in another folder. If weather.sh ever
#  grows a hidden dependency on an embedding application, that section fails.
# ============================================================================

HERE=$(dirname "$0")
MOD="$HERE/weather.sh"
[ -r "$MOD" ] || { echo "cannot find $MOD"; exit 1; }

pass=0
fail=0
check() { # $1 = what, $2 = got, $3 = want
    if [ "$2" = "$3" ]; then
        printf 'ok   %-42s %s\n' "$1" "$2"
        pass=$(( pass + 1 ))
    else
        printf 'FAIL %-42s got=%s want=%s\n' "$1" "$2" "$3"
        fail=$(( fail + 1 ))
    fi
}

TMP=$(mktemp -d 2>/dev/null || echo "/tmp/kw-test-$$")
mkdir -p "$TMP" || exit 1
UNITS=celsius
WX_CACHE_DIR="$TMP"

# ---------------------------------------------------------------------------
echo "--- standalone: the module must supply its own helpers ---"
# Wipe anything this shell might already have, then source ONLY weather.sh. A
# module that quietly needed its host would break exactly here.
unset -f log http_get is_int round0 json_section json_num json_str 2>/dev/null
. "$MOD"

_missing=""
for _f in log http_get is_int round0 json_section json_num json_str; do
    command -v "$_f" >/dev/null 2>&1 || _missing="$_missing $_f"
done
check "module defines all 7 helpers itself" "$_missing" ""
check "cache dir has a default" "$( ( unset WX_CACHE_DIR; . "$MOD"; printf '%s' "$WX_CACHE_DIR" ) | sed 's|.*/||' )" "kindle-weather"
# The module must not read an embedding application's variables. WX_CACHE_DIR
# and UNITS are the only inputs it takes, plus the optional hooks.
_smells=$(grep -nE '\$\{?(STATE_DIR|LOG_DIR|ANIM_DIR|FBINK|LOCATIONS|DASH_DIR)\b' "$MOD" 2>/dev/null | wc -l | tr -d ' ')
check "no references to host globals" "$_smells" "0"

# ---------------------------------------------------------------------------
echo
echo "--- examples in the header must be real function names ---"
for _fn in weather_fetch weather_load weather_fetch_time; do
    if command -v "$_fn" >/dev/null 2>&1; then
        check "documented API: $_fn" "ok" "ok"
    else
        check "documented API: $_fn" "missing" "ok"
    fi
done

# ---------------------------------------------------------------------------
echo
echo "--- synthetic Open-Meteo JSON (deterministic) ---"
J='{"latitude":12.97,"longitude":77.59,"timezone":"Asia/Kolkata","current_units":{"time":"iso8601","temperature_2m":"°C","weather_code":"wmo code"},"current":{"time":"2026-10-02T10:30","interval":900,"temperature_2m":27.5,"apparent_temperature":30.1,"relative_humidity_2m":68,"weather_code":61},"daily_units":{"temperature_2m_max":"°C"},"daily":{"time":["2026-10-02"],"temperature_2m_max":[31.4],"temperature_2m_min":[21.6]}}'

CUR=$(json_section "$J" current)
DAY=$(json_section "$J" daily)
check "section: current has temp"  "$(json_num "$CUR" temperature_2m)"        "27.5"
check "section: current has code"  "$(json_num "$CUR" weather_code)"         "61"
check "section: current has feels" "$(json_num "$CUR" apparent_temperature)" "30.1"
check "section: current has humid" "$(json_num "$CUR" relative_humidity_2m)" "68"
check "section: daily max"         "$(json_num "$DAY" temperature_2m_max)"   "31.4"
check "section: daily min"         "$(json_num "$DAY" temperature_2m_min)"   "21.6"
# The bug this guards: "current_units" also ends in "current" and also contains
# a "temperature_2m" key, so the unit block gets mistaken for the values.
#
# NOTE: this used to be written `json_section ... | json_num - temperature_2m`,
# which looks like it reads stdin. It does not -- json_num takes its blob as
# $1, so `-` was parsed as the blob and the check returned "" every time,
# passing for the wrong reason. Pass the section as an argument.
check "units block yields no number" "$(json_num "$(json_section "$J" current_units)" temperature_2m)" ""
check "values block does yield one"  "$(json_num "$(json_section "$J" current)" temperature_2m)"       "27.5"

JN='{"current":{"temperature_2m":-7.4,"weather_code":71},"daily":{"temperature_2m_max":[-2.5],"temperature_2m_min":[-11.2]}}'
check "negative temp"              "$(json_num "$(json_section "$JN" current)" temperature_2m)"     "-7.4"
check "negative max in array"      "$(json_num "$(json_section "$JN" daily)" temperature_2m_max)"   "-2.5"

# Pretty-printed JSON is a normal thing for a proxy to return, and every field
# silently coming back empty is a miserable bug to find. Newlines are the
# caller's job to strip; the space after the colon is the module's.
JP='{ "current": { "temperature_2m": 12.5, "weather_code": 3 } }'
check "pretty-printed: section"    "$(json_num "$(json_section "$JP" current)" temperature_2m)" "12.5"
check "pretty-printed: string"     "$(json_str '{"active":  "night"}' active)" "night"

# ---------------------------------------------------------------------------
echo
echo "--- rounding ---"
check "round 27.5"    "$(round0 27.5)"  "28"
check "round 27.4"    "$(round0 27.4)"  "27"
check "round -7.4"    "$(round0 -7.4)"  "-7"
check "round -7.6"    "$(round0 -7.6)"  "-8"
check "round 0"       "$(round0 0)"     "0"
check "round garbage" "$(round0 ab)"    "?"

echo
echo "--- WMO mapping ---"
check "code 0"    "$(wmo_text 0)"   "Clear"
check "code 2"    "$(wmo_text 2)"   "Partly cloudy"
check "code 61"   "$(wmo_text 61)"  "Light rain"
check "code 95"   "$(wmo_text 95)"  "Thunderstorm"
check "code 999"  "$(wmo_text 999)" "Unknown"
# The glyphs are three specific UTF-8 sequences, verified present in the fonts
# an e-reader ships. A stray edit here renders as a hollow box, so pin them.
check "icon 0 is U+2600"  "$(wmo_icon 0  | od -An -tx1 | tr -d ' \n')" "e29880"
check "icon 2 is U+2601"  "$(wmo_icon 2  | od -An -tx1 | tr -d ' \n')" "e29881"
check "icon 61 is U+2602" "$(wmo_icon 61 | od -An -tx1 | tr -d ' \n')" "e29882"
check "icon unknown is empty" "$(wmo_icon 999)" ""
check "prose: thunder"   "$(text_icon 'Thundery outbreaks')" "$(wmo_icon 95)"
check "prose: clear"     "$(text_icon 'Sunny')"              "$(wmo_icon 0)"
check "prose: nothing"   "$(text_icon 'Wibble')"             ""

echo
echo "--- fahrenheit conversion ---"
UNITS=celsius
check "celsius passthrough" "$(convert_units 27)" "27"
UNITS=fahrenheit
check "27C -> F"            "$(convert_units 27)"   "81"
check "0C -> F"             "$(convert_units 0)"    "32"
check "-40C -> F"           "$(convert_units -40)"  "-40"
UNITS=celsius

# ---------------------------------------------------------------------------
echo
echo "--- host hooks: an embedding app keeps its own http_get and log ---"
# This is exactly what the Kindle dashboard does: it defines util.sh's
# http_get/log BEFORE sourcing this module. The module must not clobber them,
# or the app silently loses its connection cache and its logging.
_APP_LOG=""
http_get() { _APP_HTTP_CALLED=1; printf '%s' "$J"; }
log() { _APP_LOG="$_APP_LOG."; }
json_section() { printf 'host-json-section'; }
. "$MOD"                     # re-source over the host's definitions
check "host http_get survived"    "$(command -v http_get >/dev/null 2>&1 && echo yes)" "yes"
check "host json_section survived" "$(json_section anything)" "host-json-section"
http_get "https://example.invalid/" >/dev/null
check "host http_get is the live one" "$_APP_HTTP_CALLED" "1"

# Drop the stubs again. They are guarded hooks, so the module will not overwrite
# them -- which means leaving them in place would quietly poison every parse
# test below with a json_section that returns a constant.
unset -f json_section http_get log 2>/dev/null
. "$MOD"

# ---------------------------------------------------------------------------
echo
echo "--- full fetch path, offline (http_get stubbed) ---"
FAKE="$J"
http_get() { printf '%s' "$FAKE"; }

rm -f "$TMP"/wx0.txt "$TMP"/wx1.txt
weather_fetch 0 "Home" 12.97 77.59 Asia/Kolkata
check "fetch wrote the cache line" "$(cut -d'|' -f2-9 "$TMP/wx0.txt")" "28|30|68|61|31|22|Light rain|$(wmo_icon 61)"

weather_load 0
check "load: temp"     "$WX_TEMP"     "28"
check "load: feels"    "$WX_FEELS"    "30"
check "load: humidity" "$WX_HUM"      "68"
check "load: code"     "$WX_CODE"     "61"
check "load: tmax"     "$WX_TMAX"     "31"
check "load: tmin"     "$WX_TMIN"     "22"
check "load: text"     "$WX_TEXT"     "Light rain"
check "load: icon"     "$WX_ICON"     "$(wmo_icon 61)"
check "load: label"    "$WX_LABEL"    "Home"
check "load: fetch time" "$(weather_fetch_time)" "$(date +%H:%M)"
check "fetch echoed the line" "$LAST_WX_LINE" "$(cat "$TMP/wx0.txt")"

echo
echo "--- units on the fetch path ---"
UNITS=fahrenheit
weather_fetch 0 "Home" 12.97 77.59 Asia/Kolkata
# These are NOT the exact conversions of 27.5C and 31.4C. The provider's values
# are rounded to whole degrees first, and the conversion then runs on the rounded
# numbers: 27.5 -> 28C -> 82F, where 27.5C is really 81.5F. That is a consistent
# one-degree slop paid in exchange for never showing a decimal, and it is the
# behaviour that already shipped, so it is pinned here rather than quietly
# changed underneath the user.
check "fahrenheit temp"  "$(cut -d'|' -f2 "$TMP/wx0.txt")" "82"
check "fahrenheit tmax"  "$(cut -d'|' -f6 "$TMP/wx0.txt")" "88"
check "label survives"   "$(cut -d'|' -f10 "$TMP/wx0.txt")" "Home"
UNITS=celsius

echo
echo "--- a missing daily block must not render as 31°/?° ---"
# Open-Meteo omits "daily" if the request asked only for "current".
FAKE='{"current":{"temperature_2m":9.4,"weather_code":45}}'
weather_fetch 1 "Bare" 1 2 Etc/UTC
check "tmax blanked"    "$(cut -d'|' -f6 "$TMP/wx1.txt")" ""
check "tmin blanked"    "$(cut -d'|' -f7 "$TMP/wx1.txt")" ""
check "temp still parsed" "$(cut -d'|' -f2 "$TMP/wx1.txt")" "9"
check "fog text"        "$(cut -d'|' -f8 "$TMP/wx1.txt")" "Fog"

# ---------------------------------------------------------------------------
echo
echo "--- wttr.in fallback ---"
# Branch on the URL so the primary fails and the fallback is what answers.
http_get() {
    case "$1" in
        *open-meteo*) return 1 ;;
        *wttr.in*)    printf '%s' '21.0°C|22.5°C|Light rain|87%' ;;
        *)            return 1 ;;
    esac
}
weather_fetch 0 "Home" 12.97 77.59 Asia/Kolkata
check "fallback temp"      "$(cut -d'|' -f2 "$TMP/wx0.txt")" "21"
check "fallback feels"     "$(cut -d'|' -f3 "$TMP/wx0.txt")" "23"
check "fallback humidity"  "$(cut -d'|' -f4 "$TMP/wx0.txt")" "87"
check "fallback condition" "$(cut -d'|' -f8 "$TMP/wx0.txt")" "Light rain"
check "fallback icon"      "$(cut -d'|' -f9 "$TMP/wx0.txt")" "$(wmo_icon 61)"
# wttr.in has no high/low. Empty, not "?°" and not the feels-like value.
check "fallback has no hi"  "$(cut -d'|' -f6 "$TMP/wx0.txt")" ""
check "fallback has no lo"  "$(cut -d'|' -f7 "$TMP/wx0.txt")" ""

echo
echo "--- both providers down: keep the last good reading ---"
BEFORE=$(cat "$TMP/wx0.txt")
http_get() { return 1; }
weather_fetch 0 "Home" 12.97 77.59 Asia/Kolkata
check "fetch reports failure" "$?" "1"
check "cache left untouched"  "$(cat "$TMP/wx0.txt")" "$BEFORE"
weather_load 0
check "last good reading still loads" "$WX_TEMP" "21"

echo
echo "--- a failed first fetch must not create a cache file ---"
rm -f "$TMP/wx9.txt"
weather_fetch 9 "Nowhere" 0 0 Etc/UTC
check "fetch reports failure" "$?" "1"
check "no cache file written" "$([ -e "$TMP/wx9.txt" ] && echo present || echo absent)" "absent"
weather_load 9
check "load reports no cache" "$?" "1"

# ---------------------------------------------------------------------------
if [ -n "${WEATHER_LIVE:-}" ]; then
    echo
    echo "--- live Open-Meteo (opt-in) ---"
    unset -f http_get
    . "$MOD"
    if weather_fetch 0 "Live" 12.9716 77.5946 Asia/Kolkata; then
        weather_load 0
        echo "ok   live: ${WX_TEMP}° ${WX_ICON} ${WX_TEXT} ${WX_TMAX}°/${WX_TMIN}°"
        pass=$(( pass + 1 ))
    else
        echo "skip (no network)"
    fi
fi

echo
echo "================================"
echo "passed: $pass   failed: $fail"
rm -rf "$TMP" 2>/dev/null
[ "$fail" -eq 0 ] || exit 1
