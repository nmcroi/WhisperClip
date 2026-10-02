#!/usr/bin/env python3
"""Prepare, without changing the phone, a Release DB with newer Debug recordings.

Input is a verified copy of the iPhone's Application Support directory. The
output is a NEW directory for review and later transfer to that same device.
Never overwrite a live app database with this script while the app is running.
"""

import argparse
import json
from pathlib import Path
import sqlite3
import tempfile
import uuid


def rows(db: sqlite3.Connection, table: str):
    return {row[0]: row for row in db.execute(f'SELECT * FROM {table}')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path, help='Copied iPhone Application Support')
    parser.add_argument('--output', required=True, type=Path, help='New, empty output directory')
    parser.add_argument('--seed-all-for-new-schema', action='store_true',
                        help='Queue every local transcript and note after deploying an empty Production schema')
    args = parser.parse_args()
    if args.output.exists():
        parser.error('output directory already exists')
    development = args.source / 'history-dev.db'
    release = args.source / 'history.db'
    if not (development.is_file() and release.is_file()):
        parser.error('both history variants must be present in the copied container')

    dev = sqlite3.connect(f'file:{development}?mode=ro', uri=True)
    old_release = sqlite3.connect(f'file:{release}?mode=ro', uri=True)
    try:
        for name, db in [('development', dev), ('release', old_release)]:
            if db.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
                raise RuntimeError(f'{name} database failed integrity_check')
        dev_migrations = [r[0] for r in dev.execute('SELECT identifier FROM grdb_migrations ORDER BY identifier')]
        release_migrations = [r[0] for r in old_release.execute('SELECT identifier FROM grdb_migrations ORDER BY identifier')]
        if dev_migrations != release_migrations:
            raise RuntimeError('database migrations differ; manual review required')

        dev_transcripts = rows(dev, 'transcripts')
        release_transcripts = rows(old_release, 'transcripts')
        release_only = release_transcripts.keys() - dev_transcripts.keys()
        if release_only:
            raise RuntimeError('release contains transcript IDs absent from development; manual merge required')
        dev_notes = rows(dev, 'notes')
        release_notes = rows(old_release, 'notes')
        if dev_notes != release_notes:
            raise RuntimeError('note metadata differs; manual merge required')
        differing = {key for key in dev_transcripts.keys() & release_transcripts.keys()
                     if dev_transcripts[key] != release_transcripts[key]}
        # The current device has ten duration-only differences with equal sync
        # clocks. Keep the existing Release copies rather than silently choosing
        # which audio duration should win in the CloudKit production database.
        for key in differing:
            dev_row, release_row = dev_transcripts[key], release_transcripts[key]
            if any(a != b for index, (a, b) in enumerate(zip(dev_row, release_row)) if index != 8):
                raise RuntimeError('shared transcript content differs beyond duration; manual merge required')

        missing = sorted(dev_transcripts.keys() - release_transcripts.keys())
        pending = json.loads((args.source / 'sync-pending-release.json').read_text())
        if not isinstance(pending, list):
            raise RuntimeError('release pending journal is not a list')
        if args.seed_all_for_new_schema and pending:
            raise RuntimeError('release pending journal is not empty; manual review required before full seed')
        upload_ids = sorted(dev_transcripts) if args.seed_all_for_new_schema else missing
        for key in upload_ids:
            pending.append({'op': 'upsert', 'id': key, 'token': str(uuid.uuid4()).upper()})
        if args.seed_all_for_new_schema:
            for key in sorted(dev_notes):
                pending.append({'op': 'note_upsert', 'id': key, 'token': str(uuid.uuid4()).upper()})
        with tempfile.TemporaryDirectory(prefix='.production-merge-', dir=args.output.parent) as temporary:
            stage = Path(temporary)
            merged = sqlite3.connect(stage / 'history.db')
            old_release.backup(merged)
            try:
                merged.execute('BEGIN IMMEDIATE')
                for key in missing:
                    merged.execute('INSERT INTO transcripts VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)', dev_transcripts[key])
                for table in ('ai_results', 'recording_commits', 'audio_deletions', 'audio_discarded'):
                    before = rows(merged, table)
                    for key, row in rows(dev, table).items():
                        if key in before and before[key] != row:
                            raise RuntimeError(f'conflicting {table} row; manual merge required')
                        if key not in before:
                            marks = ','.join('?' for _ in row)
                            merged.execute(f'INSERT INTO {table} VALUES ({marks})', row)
                merged.commit()
                if merged.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
                    raise RuntimeError('merged database failed integrity_check')
            finally:
                merged.close()

            (stage / 'sync-pending-release.json').write_text(json.dumps(pending, separators=(',', ':')))
            if args.seed_all_for_new_schema:
                # The old Release sidecar may hold a change token from before
                # Production had Transcript/Note. An empty file makes
                # HistorySyncEngine.loadState() start a fresh fetch while the
                # durable journal above retains every outbound record.
                (stage / 'sync-state-release.bin').write_bytes(b'')
            manifest = {
                'releaseBefore': len(release_transcripts),
                'development': len(dev_transcripts),
                'added': len(missing),
                'releaseAfter': len(release_transcripts) + len(missing),
                'durationOnlyDifferencesKeptFromRelease': len(differing),
                'noteCount': len(dev_notes),
                'pendingUpserts': len([x for x in pending if x.get('op') == 'upsert']),
                'pendingNoteUpserts': len([x for x in pending if x.get('op') == 'note_upsert']),
                'freshProductionSchemaSeed': args.seed_all_for_new_schema,
            }
            (stage / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
            stage.rename(args.output)
        print(json.dumps(manifest, indent=2))
    finally:
        dev.close()
        old_release.close()


if __name__ == '__main__':
    main()
