#!/bin/zsh
set -euo pipefail

readonly BUNDLE_ID="nl.nielscroiset.whisperclipboard.ios"
readonly PROJECT_ROOT="${0:A:h:h}"
readonly DEVICE_CONFIG="$PROJECT_ROOT/Configs/Vincent-iPhone.udid"
[[ -r "$DEVICE_CONFIG" ]] || { print -u2 "STOP: registreer Vincents toestel-ID lokaal in $DEVICE_CONFIG"; exit 1; }
readonly DEVICE_UDID="$(< "$DEVICE_CONFIG")"
[[ "$DEVICE_UDID" =~ '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}$' ]] || { print -u2 "STOP: ongeldig geregistreerd toestel-ID"; exit 1; }
readonly BACKUP_ROOT="${PROJECT_ROOT:h}/device-backups/Vincent-iPhone"

fail() {
  print -u2 "STOP: $*"
  exit 1
}

[[ $# -eq 1 ]] || fail "Gebruik: $0 /absoluut/pad/naar/WhisperClipboardiOS.app"
readonly APP_PATH="${1:A}"
[[ -d "$APP_PATH" ]] || fail "App niet gevonden: $APP_PATH"

readonly APP_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist" 2>/dev/null || true)
[[ "$APP_BUNDLE_ID" == "$BUNDLE_ID" ]] || fail "Onverwachte bundle-id: $APP_BUNDLE_ID"
/usr/bin/codesign --verify --deep --strict "$APP_PATH" || fail "Codehandtekening is ongeldig"

DEVICE_DETAILS=$(/usr/bin/xcrun devicectl device info details --device "$DEVICE_UDID" 2>&1) || fail "Vincents iPhone is niet bereikbaar"
print "$DEVICE_DETAILS" | /usr/bin/grep -q "udid: $DEVICE_UDID" || fail "Het aangesloten toestel is niet Vincents geregistreerde iPhone"

readonly STAMP=$(/bin/date '+%Y-%m-%d-%H%M%S')
readonly BACKUP_DIR="$BACKUP_ROOT/$STAMP"
readonly BEFORE_DIR="$BACKUP_DIR/before"
readonly AFTER_DIR="$BACKUP_DIR/after"
/bin/mkdir -p "$BEFORE_DIR/application-support" "$BEFORE_DIR/preferences" "$AFTER_DIR"

print "Back-up maken in $BACKUP_DIR"
/usr/bin/xcrun devicectl device copy from \
  --device "$DEVICE_UDID" \
  --domain-type appDataContainer \
  --domain-identifier "$BUNDLE_ID" \
  --source 'Library/Application Support/Whisper Clipboard v2' \
  --destination "$BEFORE_DIR/application-support" \
  --timeout 120 || fail "Back-up van Application Support is mislukt; er is niets geïnstalleerd"

# UserDefaults staat buiten Application Support. Als het plist-bestand aanwezig
# is, moet ook deze kopie slagen. Een eerste installatie kan nog geen plist hebben.
if /usr/bin/xcrun devicectl device info files \
  --device "$DEVICE_UDID" \
  --domain-type appDataContainer \
  --domain-identifier "$BUNDLE_ID" \
  --subdirectory 'Library/Preferences' \
  --no-recurse 2>/dev/null | /usr/bin/grep -q "$BUNDLE_ID.plist"; then
  /usr/bin/xcrun devicectl device copy from \
    --device "$DEVICE_UDID" \
    --domain-type appDataContainer \
    --domain-identifier "$BUNDLE_ID" \
    --source "Library/Preferences/$BUNDLE_ID.plist" \
    --destination "$BEFORE_DIR/preferences/$BUNDLE_ID.plist" \
    --timeout 30 || fail "Back-up van instellingen is mislukt; er is niets geïnstalleerd"
fi

typeset -A TRANSCRIPT_COUNTS NOTE_COUNTS
typeset found_database=0
readonly MANIFEST="$BACKUP_DIR/manifest.txt"
{
  print "device_udid=$DEVICE_UDID"
  print "bundle_id=$BUNDLE_ID"
  print "app_path=$APP_PATH"
  print "created_at=$STAMP"
} > "$MANIFEST"

for name in history-dev.db history.db; do
  db="$BEFORE_DIR/application-support/$name"
  [[ -f "$db" ]] || continue
  found_database=1
  integrity=$(/usr/bin/sqlite3 "$db" 'PRAGMA integrity_check;' 2>&1) || fail "$name kan niet worden gelezen"
  [[ "$integrity" == "ok" ]] || fail "$name is niet integer: $integrity"
  transcripts=$(/usr/bin/sqlite3 "$db" 'SELECT count(*) FROM transcripts;' 2>&1) || fail "Transcripties in $name zijn niet leesbaar"
  notes=$(/usr/bin/sqlite3 "$db" 'SELECT count(*) FROM notes;' 2>&1) || fail "Notities in $name zijn niet leesbaar"
  TRANSCRIPT_COUNTS[$name]="$transcripts"
  NOTE_COUNTS[$name]="$notes"
  /usr/bin/shasum -a 256 "$db" >> "$MANIFEST"
  print "$name integrity=ok transcripts=$transcripts notes=$notes" | /usr/bin/tee -a "$MANIFEST"
done
(( found_database == 1 )) || fail "Geen geschiedenisdatabase in de back-up gevonden"

if [[ -f "$APP_PATH/WhisperClipboardiOS.debug.dylib" ]]; then
  readonly TARGET_DB="history-dev.db"
  readonly OTHER_DB="history.db"
else
  readonly TARGET_DB="history.db"
  readonly OTHER_DB="history-dev.db"
fi

target_total=$(( ${TRANSCRIPT_COUNTS[$TARGET_DB]:-0} + ${NOTE_COUNTS[$TARGET_DB]:-0} ))
other_total=$(( ${TRANSCRIPT_COUNTS[$OTHER_DB]:-0} + ${NOTE_COUNTS[$OTHER_DB]:-0} ))
if (( target_total == 0 && other_total > 0 )); then
  fail "Deze build opent $TARGET_DB, maar Vincents gegevens staan in $OTHER_DB. Bouw het juiste type of voer eerst een gecontroleerde migratie uit."
fi

print "Back-up en databasecontrole geslaagd; update wordt nu geïnstalleerd."
/usr/bin/xcrun devicectl device install app \
  --device "$DEVICE_UDID" "$APP_PATH" --timeout 60
/usr/bin/xcrun devicectl device process launch \
  --device "$DEVICE_UDID" "$BUNDLE_ID" --timeout 30

/usr/bin/xcrun devicectl device copy from \
  --device "$DEVICE_UDID" \
  --domain-type appDataContainer \
  --domain-identifier "$BUNDLE_ID" \
  --source "Library/Application Support/Whisper Clipboard v2/$TARGET_DB" \
  --destination "$AFTER_DIR/$TARGET_DB" \
  --timeout 30 || fail "Update staat erop, maar de controlekopie na installatie is mislukt"

after_integrity=$(/usr/bin/sqlite3 "$AFTER_DIR/$TARGET_DB" 'PRAGMA integrity_check;' 2>&1) || fail "Database na installatie is niet leesbaar"
[[ "$after_integrity" == "ok" ]] || fail "Database na installatie is niet integer: $after_integrity"
after_transcripts=$(/usr/bin/sqlite3 "$AFTER_DIR/$TARGET_DB" 'SELECT count(*) FROM transcripts;')
after_notes=$(/usr/bin/sqlite3 "$AFTER_DIR/$TARGET_DB" 'SELECT count(*) FROM notes;')
print "after $TARGET_DB integrity=ok transcripts=$after_transcripts notes=$after_notes" | /usr/bin/tee -a "$MANIFEST"

(( after_transcripts >= ${TRANSCRIPT_COUNTS[$TARGET_DB]:-0} )) || fail "Er ontbreken transcripties na installatie; gebruik de back-up in $BACKUP_DIR"
(( after_notes >= ${NOTE_COUNTS[$TARGET_DB]:-0} )) || fail "Er ontbreken notities na installatie; gebruik de back-up in $BACKUP_DIR"

print "KLAAR: update en gegevens gecontroleerd. Back-up: $BACKUP_DIR"
