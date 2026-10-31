#!/usr/bin/env python3
"""One-time calibration: real classifier on known-good and corrupted logs."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('experiment',HERE/'experiment.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
results = []
with tempfile.TemporaryDirectory(prefix='dmg89-calibration-') as directory:
    m.HERE = Path(directory)
    # Integrity is tested separately below against the real frozen manifest.
    real_integrity = m.integrity
    m.integrity = lambda: []
    expected = m.HERE/'correctness/parity/jit-500000'
    expected.parent.mkdir(parents=True)
    good = b'PC=200\nCycles: 500000\nTime: 200ms\nSpeed: 2.5 MHz\n'
    Path(str(expected)+'.stdout').write_bytes(good)
    Path(str(expected)+'.stderr').write_bytes(b'')
    cases = [
        ('negative-control',good,0,b'',0,40000,True),
        ('changed-PC',good.replace(b'PC=200',b'PC=201'),0,b'',0,40000,False),
        ('missing-cycles',b'PC=200\n',0,b'',0,40000,False),
        ('duplicate-cycles',good+b'Cycles: 500000\n',0,b'',0,40000,False),
        ('short-cycles',good.replace(b'500000',b'499999'),0,b'',0,40000,False),
        ('timeout',good,124,b'',0,40000,False),
        ('nonzero',good,1,b'',0,40000,False),
        ('stderr',good,0,b'error\n',0,40000,False),
        ('thermal',good,0,b'',0,70000,False),
        ('contamination',good,0,b'',60,40000,False),
    ]
    for tag,data,status,err,busy,temp,want in cases:
        prefix = m.HERE/tag
        Path(str(prefix)+'.stdout').write_bytes(data)
        Path(str(prefix)+'.stderr').write_bytes(err)
        record = dict(name=tag,exit_status=status,timeout=status==124,
                      elapsed_ns=1000000000,child_user_s=0,child_system_s=0,
                      before={'/proc/stat':'cpu 0 0 0 0 0 0 0 0\n', '/fake/temp':'40000'},
                      after={'/proc/stat':f'cpu {busy} 0 0 0 0 0 0 0\n','/fake/temp':str(temp)})
        m.classify(record,'jit')
        assert record['valid'] == want, tag
        results.append({'case':tag,'expected_valid':want,'valid':record['valid'],
                        'reasons':record['exclusion_reasons']})
    m.HERE = HERE
    m.integrity = real_integrity
    assert not m.integrity()
    # Corrupt a recorded expected source hash in a scratch copy of the manifest.
    manifest = json.loads((HERE/'manifest.json').read_text())
    first = next(iter(manifest['source_content_sha256']['DMG']))
    manifest['source_content_sha256']['DMG'][first] = '0'*64
    m.HERE = Path(directory)
    (m.HERE/'manifest.json').write_text(json.dumps(manifest))
    assert 'DMG source content changed' in m.integrity()
    results.append({'case':'source-hash-mutant','caught':True})
    # An interrupted attempt reserves its name even without a final record.
    (m.HERE/'reserved.started.json').write_text('{}')
    try:
        m.run('reserved',['/bin/true'])
    except RuntimeError:
        results.append({'case':'interrupted-attempt-no-overwrite','caught':True})
    else:
        raise AssertionError('overwrote interrupted attempt')
(HERE/'calibration.json').write_text(json.dumps(results,indent=2)+'\n')
print(f'CALIBRATION {len(results)}/{len(results)} passed')
