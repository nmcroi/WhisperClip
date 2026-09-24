#!/bin/zsh
# Read-only compatibility checks followed by a local backup. Never replaces an app or database.
set -eu
finish() { print "\n$1"; read '?Druk op Enter om te sluiten.'; }
if pgrep -x WhisperClip >/dev/null; then
  finish 'Stop WhisperClip eerst via Cmd-Q, zodat geen opname of databasewijziging loopt. Open dit bestand daarna opnieuw.'
  exit 1
fi
candidate_apps=()
for candidate in /Applications/WhisperClip.app "$HOME/Applications/WhisperClip.app"; do
  [[ -d "$candidate" ]] && candidate_apps+=("$candidate")
done
if (( ${#candidate_apps} > 1 )); then
  finish 'Er staan twee exemplaren van WhisperClip. Laat eerst bepalen welk exemplaar je gebruikt; vervang nu niets.'
  exit 1
fi
if (( ${#candidate_apps} == 1 )); then
  signed_info=$(codesign -d --entitlements :- "${candidate_apps[1]}" 2>/dev/null) || { finish 'Ondertekening bestaande app niet leesbaar. Vervang nu niets.'; exit 1; }
  if [[ "$signed_info" == *'<string>Development</string>'* ]]; then
    finish 'Dit is een ontwikkelversie met een andere iCloud-omgeving. Deze DMG niet installeren; laat eerst de gegevensovergang voorbereiden.'
    exit 1
  fi
fi
data_dir="$HOME/Library/Application Support/Whisper Clipboard v2"
production_count=0
development_count=0
for db_name in history.db history-dev.db; do
  db_path="$data_dir/$db_name"
  if [[ -f "$db_path" ]]; then
    [[ "$(sqlite3 -readonly "$db_path" 'PRAGMA integrity_check;')" == 'ok' ]] || { finish 'Databasecontrole mislukt. Niet installeren.'; exit 1; }
    row_count=$(sqlite3 -readonly "$db_path" 'SELECT COUNT(*) FROM transcripts;')
    note_count=0
    if [[ "$(sqlite3 -readonly "$db_path" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='notes';")" == 1 ]]; then
      note_count=$(sqlite3 -readonly "$db_path" 'SELECT COUNT(*) FROM notes;')
    fi
    print "$db_name: $row_count transcripties, integriteit OK"
    if [[ "$db_name" == history.db ]]; then production_count=$row_count; else development_count=$((row_count + note_count)); fi
  fi
done
if (( development_count > 0 )); then
  finish 'Er staan ook gegevens in de ontwikkelvariant. Laat eerst vaststellen welke geschiedenis je gebruikt en de overgang voorbereiden. Niet installeren.'
  exit 1
fi
backup_dir="$HOME/Library/Application Support/WhisperClip Backups/$(date +%Y-%m-%d-%H%M%S)"
mkdir -p "$backup_dir"
[[ ! -d "$data_dir" ]] || ditto "$data_dir" "$backup_dir/ApplicationSupport"
preferences_file="$HOME/Library/Preferences/nl.nielscroiset.whisperclipboard.plist"
[[ ! -f "$preferences_file" ]] || cp "$preferences_file" "$backup_dir/preferences.plist"
if (( ${#candidate_apps} == 1 )); then
  ditto "${candidate_apps[1]}" "$backup_dir/WhisperClip.app"
  print "Bestaande app: ${candidate_apps[1]}"
fi
for db_name in history.db history-dev.db; do
  [[ ! -f "$backup_dir/ApplicationSupport/$db_name" ]] || \
    [[ "$(sqlite3 -readonly "$backup_dir/ApplicationSupport/$db_name" 'PRAGMA integrity_check;')" == 'ok' ]]
done
finish "Controle en backup geslaagd.\nBackup: $backup_dir\nVervang nu de bestaande app op dezelfde locatie met WhisperClip uit deze DMG.\nVerwijder geen appgegevens."
