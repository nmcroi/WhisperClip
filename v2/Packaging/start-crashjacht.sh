#!/bin/zsh
# Start de crashjacht-build van WhisperClip mét de jachtomgeving.
#
# Waarom dit script bestaat (22 augustus 2026): de jachtversie draaide van 15
# tot 20 augustus vanuit een shell met ASAN_OPTIONS en de strikte Swift
# 6-isolatiestand. Toen hij op 20 augustus om 18:50 omviel, startte Niels hem
# via de Dock opnieuw. Die herstart verliest de hele omgeving: ASan schrijft
# dan nergens meer naartoe en breekt bij de eerste fout af, en de strikte stand
# staat uit. Niemand merkte dat, vijf dagen lang. Met dit script staat de
# omgeving vast en wordt het logpad afgedrukt.
#
# Dit is GEEN dagelijkse app. Address Sanitizer maakt de app twee tot vijf
# keer trager en de strikte stand laat hem bewust omvallen bij de eerste
# isolatie-overtreding. Gebruik hem alleen voor een bewuste jachtronde, en zet
# daarna de gewone build terug (~/Applications/WhisperClip.app).
#
# Bouwen gaat vooraf met:
#   cd v2 && xcodebuild -project WhisperClipboard.xcodeproj \
#     -scheme WhisperClipboard-Crashjacht -configuration Debug \
#     -destination 'platform=macOS' -derivedDataPath /tmp/whisperclip-asan-dd \
#     ENABLE_ADDRESS_SANITIZER=YES OTHER_SWIFT_FLAGS='$(inherited) -sanitize=address' build
# Let op: -enableAddressSanitizer YES op de commandoregel alleen instrumenteert
# de C-delen, niet de Swift-code. Daarom de twee build-instellingen.

set -u
APP="/tmp/whisperclip-asan-dd/Build/Products/Debug/WhisperClip.app"
BIN="$APP/Contents/MacOS/WhisperClip"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="/tmp/whisperclip-jacht-$STAMP.log"
ASAN_LOG="/tmp/whisperclip-asan"   # ASan plakt er zelf .<pid> achter

if [[ ! -x "$BIN" ]]; then
  echo "Geen jachtbuild gevonden op $APP. Bouw hem eerst, zie de kop van dit script." >&2
  exit 1
fi
if ! otool -L "$APP/Contents/MacOS/WhisperClip.debug.dylib" 2>/dev/null | grep -q asan; then
  echo "Waarschuwing: deze build draagt geen Address Sanitizer. Dan jaag je met een lege loop." >&2
fi

# Een lopende WhisperClip (dagelijks of jacht) eerst netjes afsluiten: twee
# instanties delen dezelfde geschiedenis-database.
osascript -e 'quit app "WhisperClip"' >/dev/null 2>&1
sleep 2
pkill -f "WhisperClip.app/Contents/MacOS/WhisperClip" >/dev/null 2>&1
sleep 1

# MODE: "asan" (standaard) of "strict" voor alleen de isolatiecontrole zonder
# sanitizer, een stuk sneller en genoeg om een isolatiefout te laten klappen.
MODE="${1:-asan}"
case "$MODE" in
  asan)
    export ASAN_OPTIONS="detect_stack_use_after_return=1:log_path=$ASAN_LOG:print_stats=0:abort_on_error=0:halt_on_error=0"
    export MallocNanoZone=0
    ;;
  strict)
    unset ASAN_OPTIONS
    ;;
  *)
    echo "Gebruik: $0 [asan|strict]" >&2; exit 2 ;;
esac
# De strikte stand van de Swift 6-isolatiecontrole: valt meteen om op de eerste
# overtreding, met een bruikbare stack, in plaats van soms.
export SWIFT_IS_CURRENT_EXECUTOR_LEGACY_MODE_OVERRIDE=swift6

nohup "$BIN" > "$LOG" 2>&1 &
sleep 3
if pgrep -f "whisperclip-asan-dd" >/dev/null; then
  echo "Jachtversie draait (stand: $MODE)."
  echo "  applog:    $LOG"
  echo "  ASan:      $ASAN_LOG.<pid>  (alleen bij een vondst)"
  echo "  crashes:   ~/Library/Logs/Whisper Clipboard/crash-*.txt en ~/Library/Logs/DiagnosticReports/"
  echo "Terug naar de gewone app: sluit WhisperClip af en open ~/Applications/WhisperClip.app."
else
  echo "Starten mislukt, kijk in $LOG" >&2; exit 1
fi
