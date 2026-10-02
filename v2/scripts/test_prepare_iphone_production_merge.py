import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).with_name('prepare_iphone_production_merge.py')


def make_database(path: Path, transcript_ids: list[str]):
    with sqlite3.connect(path) as db:
        db.executescript('''
            CREATE TABLE grdb_migrations (identifier TEXT PRIMARY KEY);
            INSERT INTO grdb_migrations VALUES ('v1');
            CREATE TABLE transcripts (
              id TEXT PRIMARY KEY, text TEXT, created_at TEXT, name TEXT,
              pinned INTEGER, language TEXT, model TEXT, source TEXT,
              duration REAL, segments TEXT, sort_key REAL, speaker_names TEXT,
              modified_at INTEGER, note_id TEXT);
            CREATE TABLE notes (id TEXT PRIMARY KEY, title TEXT, created_at TEXT,
                                modified_at TEXT, sort_key REAL);
            CREATE TABLE ai_results (id TEXT PRIMARY KEY, transcript_id TEXT,
                                     mode_id TEXT, mode_name TEXT, output TEXT, created_at TEXT);
            CREATE TABLE recording_commits (id TEXT PRIMARY KEY);
            CREATE TABLE audio_deletions (id TEXT PRIMARY KEY);
            CREATE TABLE audio_discarded (id TEXT PRIMARY KEY);
        ''')
        for item in transcript_ids:
            db.execute('INSERT INTO transcripts VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
                       (item, 'text-' + item, '2026-10-02T10:00:00Z', '', 0, 'nl',
                        'parakeet', 'plaud.ios', 12.0, '[]', 0.0, '{}', 100, None))


class ProductionMergeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.source = self.base / 'source'
        self.source.mkdir()

    def run_merge(self, *extra):
        return subprocess.run([sys.executable, SCRIPT, '--source', self.source,
                               '--output', self.base / 'prepared', *extra],
                              capture_output=True, text=True)

    def test_missing_records_are_queued_without_changing_copies(self):
        make_database(self.source / 'history-dev.db', ['old', 'new'])
        make_database(self.source / 'history.db', ['old'])
        (self.source / 'sync-pending-release.json').write_text('[]')
        result = self.run_merge()
        self.assertEqual(result.returncode, 0, result.stderr)
        with sqlite3.connect(self.base / 'prepared/history.db') as db:
            self.assertEqual(db.execute('SELECT count(*) FROM transcripts').fetchone()[0], 2)
            self.assertEqual(db.execute('PRAGMA integrity_check').fetchone()[0], 'ok')
        with sqlite3.connect(self.source / 'history.db') as db:
            self.assertEqual(db.execute('SELECT count(*) FROM transcripts').fetchone()[0], 1)
        pending = json.loads((self.base / 'prepared/sync-pending-release.json').read_text())
        self.assertEqual([(item['op'], item['id']) for item in pending], [('upsert', 'new')])

    def test_release_only_record_aborts_before_output(self):
        make_database(self.source / 'history-dev.db', ['new'])
        make_database(self.source / 'history.db', ['old'])
        (self.source / 'sync-pending-release.json').write_text('[]')
        result = self.run_merge()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.base / 'prepared').exists())

    def test_conflicting_shared_text_aborts_before_output(self):
        make_database(self.source / 'history-dev.db', ['old'])
        make_database(self.source / 'history.db', ['old'])
        with sqlite3.connect(self.source / 'history-dev.db') as db:
            db.execute("UPDATE transcripts SET text='different' WHERE id='old'")
        (self.source / 'sync-pending-release.json').write_text('[]')
        result = self.run_merge()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.base / 'prepared').exists())

    def test_new_production_schema_queues_old_and_new_records_and_notes(self):
        make_database(self.source / 'history-dev.db', ['old', 'new'])
        make_database(self.source / 'history.db', ['old'])
        for name in ('history-dev.db', 'history.db'):
            with sqlite3.connect(self.source / name) as db:
                db.execute("INSERT INTO notes VALUES ('note-1','title','created','modified',0)")
        (self.source / 'sync-pending-release.json').write_text('[]')
        (self.source / 'sync-state-release.bin').write_bytes(b'old-change-token')
        result = self.run_merge('--seed-all-for-new-schema')
        self.assertEqual(result.returncode, 0, result.stderr)
        pending = json.loads((self.base / 'prepared/sync-pending-release.json').read_text())
        self.assertEqual({(item['op'], item['id']) for item in pending},
                         {('upsert', 'old'), ('upsert', 'new'), ('note_upsert', 'note-1')})
        self.assertEqual((self.base / 'prepared/sync-state-release.bin').read_bytes(), b'')
        self.assertEqual((self.source / 'sync-state-release.bin').read_bytes(), b'old-change-token')

    def test_full_seed_rejects_existing_unsent_changes(self):
        make_database(self.source / 'history-dev.db', ['old'])
        make_database(self.source / 'history.db', ['old'])
        (self.source / 'sync-pending-release.json').write_text(
            '[{"op":"delete","id":"other","token":"keep"}]')
        result = self.run_merge('--seed-all-for-new-schema')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.base / 'prepared').exists())


if __name__ == '__main__':
    unittest.main()
