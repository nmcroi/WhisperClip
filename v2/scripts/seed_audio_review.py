#!/usr/bin/env python3
"""Synthetic UI fixture. Refuses any simulator not explicitly named for this review."""
import json
import math
from pathlib import Path
import sqlite3
import struct
import subprocess
import sys
import wave

device = sys.argv[1]
devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', '--json']))
selected = [d for group in devices['devices'].values() for d in group if d['udid'] == device]
assert len(selected) == 1 and selected[0]['name'].startswith('WhisperClip Audio Review'), 'Use an isolated audio review simulator'
bundle = 'nl.nielscroiset.whisperclipboard.ios'
subprocess.run(['xcrun', 'simctl', 'terminate', device, bundle], capture_output=True)
container = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', device, bundle, 'data'], text=True).strip())
base = container / 'Library/Application Support/Whisper Clipboard v2'
assert (base / 'history-dev.db').is_file(), 'Launch the Debug app once to create its database'
recordings = base / 'Audio-dev/Recordings'
recordings.mkdir(parents=True, exist_ok=True)
with wave.open(str(recordings / 'audio-review-fixture.wav'), 'wb') as audio:
    audio.setnchannels(1); audio.setsampwidth(2); audio.setframerate(16000)
    audio.writeframes(b''.join(struct.pack('<h', int(math.sin(i * math.tau * 440 / 16000) * 4000)) for i in range(16000 * 3)))
with sqlite3.connect(base / 'history-dev.db') as db:
    for table in ['audio_deletions', 'audio_discarded', 'recording_commits']:
        db.execute(f'DELETE FROM {table} WHERE id = ?', ('audio-review-fixture',))
    db.execute('''INSERT OR REPLACE INTO transcripts
        (id, text, created_at, name, pinned, language, model, source, duration, segments, sort_key, modified_at)
        VALUES (?, ?, ?, ?, 0, 'nl', 'synthetic-fixture', 'mic.ios', 3, '[]', 1789308000, 1789308000000)''',
        ('audio-review-fixture', 'Synthetische testaudio, geen echte opname.', '2026-09-13T14:00:00Z', 'Audio review fixture'))
print('Synthetic fixture created in isolated simulator', device)
