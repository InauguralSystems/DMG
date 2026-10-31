#!/usr/bin/env python3
"""Lossless child logging adapter for the unchanged Blargg shell gates."""
import json
import os
from pathlib import Path
import resource
import signal
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
arm = os.environ['RECEIPT_ARM']
args = sys.argv[1:]
cmd = [ROOT/'.bench-build/dmg-aot', *args[1:]] if arm == 'aot' else [
    ROOT/'.bench-build/eigs-dmg/build/release/eigenscript', *args]
tag = '-'.join(Path(args[1]).relative_to(ROOT/'roms').parts).replace('.gb','')
prefix = HERE/'correctness'/arm/'children'/tag
prefix.parent.mkdir(parents=True, exist_ok=True)
if list(prefix.parent.glob(prefix.name+'.*')):
    raise RuntimeError('refusing child log overwrite')
resource.setrlimit(resource.RLIMIT_AS, (1500000*1024,1500000*1024))
Path(str(prefix)+'.started.json').write_text(json.dumps({
    'command':list(map(str,cmd)), 'arm':arm,'limit_KiB':1500000,
    'started_unix_ns':time.time_ns()})+'\n')
def interrupted(signum, frame):
    Path(str(prefix)+'.signal.json').write_text(json.dumps({
        'signal':signum,'unix_ns':time.time_ns()})+'\n')
signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGINT, interrupted)
with open(str(prefix)+'.stdout','wb') as out, open(str(prefix)+'.stderr','wb') as err:
    r = subprocess.run(list(map(str,cmd)),stdout=out,stderr=err)
Path(str(prefix)+'.json').write_text(json.dumps({
    'command':list(map(str,cmd)), 'exit_status':r.returncode,
    'arm':arm,'limit_KiB':1500000})+'\n')
sys.stdout.buffer.write(Path(str(prefix)+'.stdout').read_bytes())
sys.stderr.buffer.write(Path(str(prefix)+'.stderr').read_bytes())
sys.exit(r.returncode)
