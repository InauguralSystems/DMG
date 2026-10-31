#!/usr/bin/env python3
"""Postcollection provenance/conditions and final artifact checksums."""
import datetime
import importlib.util
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('experiment',HERE/'experiment.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
if len(sys.argv)>1 and sys.argv[1]=='indexes':
    attempts = []
    for p in sorted(HERE.rglob('*.json')):
        if p.name.endswith('.started.json') or '__pycache__' in p.parts:
            continue
        obj = json.loads(p.read_text())
        if not isinstance(obj,dict) or 'command' not in obj or 'exit_status' not in obj:
            continue
        attempts.append(dict(evidence=str(p.relative_to(HERE)),
                             role='ROM child' if 'children' in p.parts else 'recorded command',
                             command=obj['command'],exit_status=obj['exit_status']))
    m.write(HERE/'attempt-index.json',attempts)
    m.write(HERE/'failure-index.json',[a for a in attempts if a['exit_status'] != 0])
    print(f'INDEXED {len(attempts)} command/child records; failures include parent and child statuses separately')
    raise SystemExit(0)
if len(sys.argv)>1 and sys.argv[1]=='hashes':
    lines = []
    for p in sorted(HERE.rglob('*')):
        if p.is_file() and '__pycache__' not in p.parts and p.name != 'SHA256SUMS':
            lines.append(m.sha(p)+'  '+str(p.relative_to(HERE)))
    (HERE/'SHA256SUMS').write_text('\n'.join(lines)+'\n')
    print(f'CHECKSUMS {len(lines)} files')
    raise SystemExit(0)

records = [json.loads(p.read_text()) for p in (HERE/'samples').glob('*.json')
           if not p.name.endswith('.started.json')]
started = list((HERE/'samples').glob('*.started.json'))
assert len(records)==len(started)==21
changes = m.integrity()
assert not changes, changes
temps,loads,available,excess = [],[],[],[]
for r in records:
    excess.append(r['excess_host_busy_cpu_equivalents'])
    for side in ('before','after'):
        s = r[side]
        temps += [int(v)/1000 for k,v in s.items() if k.endswith('/temp') and v.strip().isdigit()]
        loads.append(float(s['/proc/loadavg'].split()[0]))
        available.append(int(next(line.split()[1] for line in s['/proc/meminfo'].splitlines()
                                  if line.startswith('MemAvailable:'))))
out = dict(checked_utc=m.utc(),integrity_changes=changes,
           manifest_sha256=m.sha(HERE/'manifest.json'),
           started_samples=len(started),completed_samples=len(records),
           valid_samples=sum(r['valid'] for r in records),
           actual_cycle_counts=sorted({r['actual_cycles'] for r in records}),
           measured_start_utc=min(r['started_utc'] for r in records),
           measured_end_utc=max(r['ended_utc'] for r in records),
           pre_post_temperature_C_range=[min(temps),max(temps)],
           one_minute_load_range=[min(loads),max(loads)],
           available_memory_KiB_range=[min(available),max(available)],
           excess_host_busy_cpu_equivalents_range=[min(excess),max(excess)],
           exclusions=[{'name':r['name'],'reasons':r['exclusion_reasons']} for r in records if not r['valid']],
           measurement_failures=[r['name'] for r in records if r['exit_status']],
           note='Verified before the requested BASELINE.md documentation edit; no workload re-executed.')
m.write(HERE/'postcollection-audit.json',out)
print(json.dumps(out,indent=2))
