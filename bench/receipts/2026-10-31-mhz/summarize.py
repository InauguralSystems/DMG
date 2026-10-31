#!/usr/bin/env python3
"""Derive statistics from every retained sample; no workload execution."""
import csv
import json
from pathlib import Path
from statistics import median

HERE = Path(__file__).resolve().parent

def stats(values):
    if not values:
        return None
    values = sorted(values)
    n = len(values)
    lo = values[:n//2]
    hi = values[(n+1)//2:]
    q1 = median(lo) if lo else values[0]
    q3 = median(hi) if hi else values[-1]
    return dict(n=n,median=median(values),min=values[0],max=values[-1],
                q1=q1,q3=q3,iqr=q3-q1)

records = []
for p in sorted((HERE/'samples').glob('*.json')):
    if p.name.endswith('.started.json'):
        continue
    r = json.loads(p.read_text())
    r['round'] = int(p.stem.split('-',1)[0])
    r['label'] = p.stem.split('-',1)[1]
    r['evidence'] = str(p.relative_to(HERE))
    records.append(r)
summary = {'arms':{}, 'paired':{}, 'all_attempts':len(records)}
for label in ('interpreter','jit','jit-repeat'):
    group = [r for r in records if r['label']==label]
    valid = [r for r in group if r['valid']]
    summary['arms'][label] = dict(scheduled=7,attempted=len(group),valid=len(valid),
                                wall_seconds=stats([r['wall_seconds'] for r in valid]),
                                mhz=stats([r['mhz'] for r in valid]),
                                exclusions=[{'evidence':r['evidence'],'reasons':r['exclusion_reasons']}
                                            for r in group if not r['valid']])
for first,second in [('interpreter','jit'),('jit','jit-repeat')]:
    pairs = []
    for rep in range(1,8):
        a = next((r for r in records if r['round']==rep and r['label']==first and r['valid']),None)
        b = next((r for r in records if r['round']==rep and r['label']==second and r['valid']),None)
        if a and b:
            pairs.append(dict(round=rep,wall_delta_s=b['wall_seconds']-a['wall_seconds'],
                              wall_delta_percent=(b['wall_seconds']/a['wall_seconds']-1)*100,
                              mhz_delta_percent=(b['mhz']/a['mhz']-1)*100))
    summary['paired'][first+' -> '+second] = dict(
        n=len(pairs),pairs=pairs,
        wall_delta_seconds=stats([p['wall_delta_s'] for p in pairs]),
        wall_delta_percent=stats([p['wall_delta_percent'] for p in pairs]),
        absolute_wall_delta_percent=stats([abs(p['wall_delta_percent']) for p in pairs]),
        mhz_delta_percent=stats([p['mhz_delta_percent'] for p in pairs]))
(HERE/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
with (HERE/'raw-samples.csv').open('w') as f:
    fields = ['round','label','started_utc','exit_status','timeout','actual_cycles',
              'elapsed_ns','wall_seconds','mhz','valid',
              'excess_host_busy_cpu_equivalents','exclusion_reasons','evidence']
    writer = csv.DictWriter(f,fieldnames=fields,extrasaction='ignore')
    writer.writeheader()
    writer.writerows(records)
for label,a in summary['arms'].items():
    print(label,json.dumps(a))
for label,p in summary['paired'].items():
    print(label,json.dumps({k:v for k,v in p.items() if k!='pairs'}))
