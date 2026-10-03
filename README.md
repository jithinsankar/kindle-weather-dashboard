# kindle-weather-dashboard

The weather engine for the Kindle lock-screen dashboard: fetch, parse, cache --
with nothing but a POSIX shell.

> **What is in here today is the engine only.** There is no display code, because
> the lock screen's rendering shares its fbink measurement and chained-vertical-
> placement machinery with the clock, and that still lives in the dashboard
> project. This repository is the part that is genuinely independent: HTTP in,
> one line of text out.

Downloads current conditions and today's high/low from a keyless HTTP API and
caches them as **one line of pipe-separated text**. That single line is the whole
point: an e-reader has no `jq`, no Python and no JSON library, and one line is
trivial for any shell to read back.

```sh
. ./weather.sh
weather_fetch 0 "Home" 12.97 77.59 Asia/Kolkata   # download + cache
weather_load  0                                   # -> WX_* variables
printf '%s\n' "$WX_TEMP° $WX_ICON $WX_TEXT"
```

No API key. No account. No dependencies beyond `sh`, `sed`, `awk` and `curl`
(or `wget`).

## Why this is its own repository

It has nothing to do with e-ink, framebuffers, screensavers, clocks or layout.
It is HTTP in, one line of text out, and it runs the same on a Kindle, a laptop,
a router or a Raspberry Pi. Keeping it separate means it can be tested on a
desktop with no device attached, and reused by anything else that wants a
weather reading without dragging a display stack along.

## Providers

| Order | Provider | Notes |
|---|---|---|
| 1 | [open-meteo.com](https://open-meteo.com) | No API key. Compact JSON, 15-minute resolution. Gives high/low and a WMO code |
| 2 | [wttr.in](https://wttr.in) | Plain text. Used only when open-meteo fails. No high/low, no condition code |

If both fail, `weather_fetch` returns non-zero and **leaves the previous cache
untouched** — a failed refresh must never blank a good reading.

## API

| Function | Purpose |
|---|---|
| `weather_fetch <idx> <label> <lat> <lon> <tz>` | Fetch, cache, and echo the cache line. Non-zero on failure |
| `weather_load <idx>` | Read the cache into `WX_*` variables. Non-zero if absent |
| `weather_fetch_time` | Echo the HH:MM of the last successful fetch for index 0 |
| `convert_units <celsius>` | Convert per `$UNITS`. Rounds rather than truncates |
| `wmo_text <code>` / `wmo_icon <code>` | WMO code to words / to one of three glyphs |
| `text_icon <prose>` | The same glyphs, from a wttr.in condition string |

Set after `weather_load`:

```
WX_EPOCH  WX_TEMP  WX_FEELS  WX_HUM  WX_CODE
WX_TMAX   WX_TMIN  WX_TEXT   WX_ICON WX_LABEL  WX_FETCH_HHMM
```

## Cache format

One line, pipe separated, in `$WX_CACHE_DIR/wx<idx>.txt`:

```
epoch|temp|feels|humidity|code|tmax|tmin|text|icon|label|fetchtime
```

Temperatures are stored as whole numbers in `$UNITS`. `tmax`/`tmin` are empty
when the provider does not know them (wttr.in never does) — empty rather than
`?`, so a caller can decide whether to render them.

## Settings

| Variable | Default | Meaning |
|---|---|---|
| `WX_CACHE_DIR` | `${TMPDIR:-/tmp}/kindle-weather` | Where the cache lives |
| `UNITS` | `celsius` | `celsius` or `fahrenheit` |

## Host contract

The module is self-contained: source it and it works. But if the host has
**already defined** any of the helpers below, the host's version wins. That is
guarded with `command -v` for every one of them, so an embedding application
keeps its own HTTP stack (with its connection caching) and its own logging:

```
log   http_get   is_int   round0   json_section   json_num   json_str
```

Embedding it is therefore safe and does not require this module to know anything
about the host. `UNITS`, `CURL_BIN`, `WGET_BIN`, `LOG_FILE` and `TMPDIR` are read
if the host sets them, and have working fallbacks if it does not.

## Tests

```sh
sh test.sh              # offline, deterministic
WEATHER_LIVE=1 sh test.sh   # also hits the live API
```

75 assertions, no network required. The first block asserts that the module
supplies all seven helpers itself, so if `weather.sh` ever grows a hidden
dependency on an embedding application, that block fails.

## Glyphs

`wmo_icon` returns exactly three characters — U+2600 ☀, U+2601 ☁, U+2602 ☂ —
chosen because they are present in the fonts an e-reader actually ships (on the
Kindle they were verified in `NotoSansCJKsc-Regular.otf`). Anything fancier
renders as a hollow box, which reads as a bug rather than as weather.
