import tempfile, pathlib, subprocess, sqlite3, os
source=pathlib.Path('v2/Packaging/Controleer en maak backup.command').read_text()
for case in ['release','development','dev-only','both','dev-notes','corrupt','duplicate']:
 with tempfile.TemporaryDirectory() as d:
  root=pathlib.Path(d); home=root/'home';data=home/'Library/Application Support/Whisper Clipboard v2';data.mkdir(parents=True)
  app=home/'Applications/WhisperClip.app';app.mkdir(parents=True);(app/'fixture.txt').write_text('app')
  for name,n in [('history.db',2),('history-dev.db',1 if case in ['dev-only','both'] else 0)]:
   if name=='history.db' and case=='dev-only':continue
   with sqlite3.connect(data/name) as c:
    c.execute('create table transcripts(id text)');c.executemany('insert into transcripts values (?)',[(str(i),) for i in range(n)])
    c.execute('create table notes(id text)')
    if case=='dev-notes' and name=='history-dev.db':c.execute("insert into notes values ('note')")
  if case=='corrupt':(data/'history.db').write_bytes(b'bad database')
  if case=='duplicate':(root/'global/WhisperClip.app').mkdir(parents=True)
  fake=root/'bin';fake.mkdir()
  for name,body in [('pgrep','exit 1'),('codesign','printf \'<plist><dict><key>env</key><string>'+('Development' if case=='development' else 'Production')+'</string></dict></plist>\'')]:
   p=fake/name;p.write_text('#!/bin/sh\n'+body+'\n');p.chmod(0o755)
  script=root/'check.command';script.write_text(source.replace('/Applications/WhisperClip.app',str(root/'global/WhisperClip.app'),1).replace('$HOME',str(home)))
  env=os.environ.copy();env['PATH']=str(fake)+':'+env['PATH']
  r=subprocess.run(['zsh',str(script)],input='\n',text=True,capture_output=True,env=env)
  backups=list((home/'Library/Application Support/WhisperClip Backups').glob('*'))
  if case=='release':
   assert r.returncode==0,(case,r.stderr)
   assert len(backups)==1
   with sqlite3.connect(backups[0]/'ApplicationSupport/history.db') as c:assert c.execute('select count(*) from transcripts').fetchone()[0]==2
  else:assert r.returncode!=0 and not backups,(case,r.stdout,r.stderr)
  print(case+': PASS')
