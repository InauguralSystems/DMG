#!/usr/bin/env python3
"""One-off receipt runner. Run phases separately; never retries a workload."""
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import subprocess as sp
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
BUILD = ROOT / '.bench-build'
EIGS = BUILD / 'eigs-dmg'
OURO = BUILD / 'ouroboros'
VM = EIGS / 'build/release/eigenscript'
AOT = BUILD / 'dmg-aot'
ROM = ROOT / 'roms/cpu_instrs.gb'
LIMIT = 1500000 * 1024

def utc():
    return dt.datetime.now(dt.timezone.utc).isoformat()

def sha(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()

def write(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, indent=2) + '\n')

def cleanenv(arm='jit'):
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(('EIGS', 'EIGENSCRIPT', 'AOT_', 'K_', 'BLARGG_', 'MALLOC_'))
           and k not in ('ASAN_OPTIONS', 'UBSAN_OPTIONS', 'LSAN_OPTIONS',
                         'TSAN_OPTIONS', 'LD_PRELOAD', 'MAKEFLAGS', 'CC', 'CFLAGS', 'LDFLAGS')}
    env.update(LC_ALL='C', TZ='UTC')
    if arm == 'interpreter':
        env['EIGS_JIT_OFF'] = '1'
    return env

def host():
    paths = ['/proc/loadavg', '/proc/stat', '/proc/meminfo', '/proc/pressure/cpu',
             '/proc/pressure/memory', '/proc/pressure/io', '/proc/self/status']
    for pattern in ('/sys/class/thermal/thermal_zone*/type',
                    '/sys/class/thermal/thermal_zone*/temp',
                    '/sys/devices/system/cpu/cpu*/cpufreq/scaling_*',
                    '/sys/devices/system/cpu/cpu*/thermal_throttle/*',
                    '/sys/class/power_supply/*/online'):
        import glob
        paths += glob.glob(pattern)
    out = {'utc': utc()}
    for p in paths:
        try:
            out[p] = Path(p).read_text()
        except OSError as e:
            out[p] = str(e)
    return out

def run(name, cmd, arm='jit', seconds=180, envextra=None):
    prefix = HERE / name
    prefix.parent.mkdir(parents=True, exist_ok=True)
    if list(prefix.parent.glob(prefix.name+'.*')):
        raise RuntimeError(f'refusing to overwrite/retry {name}')
    env = cleanenv(arm)
    env.update(envextra or {})
    command = ['timeout', '--signal=TERM', '--kill-after=5', str(seconds)] + list(map(str, cmd))
    before = host()
    started = utc()
    write(Path(str(prefix)+'.started.json'),
          dict(command=command,arm=arm,started_utc=started,limit_KiB=1500000))
    r0 = resource.getrusage(resource.RUSAGE_CHILDREN)
    with open(str(prefix) + '.stdout', 'wb') as out, open(str(prefix) + '.stderr', 'wb') as err:
        t0 = time.perf_counter_ns()
        result = sp.run(command, cwd=ROOT, env=env, stdout=out, stderr=err)
        t1 = time.perf_counter_ns()
    r1 = resource.getrusage(resource.RUSAGE_CHILDREN)
    after = host()
    record = dict(name=name, arm=arm, command=command, cwd=str(ROOT),
                  started_utc=started, ended_utc=utc(), exit_status=result.returncode,
                  timeout=result.returncode in (124, 137), elapsed_ns=t1-t0,
                  child_user_s=r1.ru_utime-r0.ru_utime,
                  child_system_s=r1.ru_stime-r0.ru_stime,
                  environment_overrides={k:v for k,v in env.items()
                                         if k.startswith(('EIGS', 'RECEIPT', 'K_', 'DMG_', 'AOT_'))
                                         or k in ('LC_ALL', 'TZ')},
                  before=before, after=after)
    write(Path(str(prefix) + '.json'), record)
    print(f'{name}: rc={result.returncode}', flush=True)
    return record

def norm(data):
    return b''.join(line for line in data.splitlines(keepends=True)
                    if not line.startswith((b'Time: ', b'Speed: ')))

def cycles(data):
    matches = re.findall(rb'^Cycles: ([0-9]+)$', data, re.M)
    if len(matches) != 1:
        raise ValueError(f'expected one cycle report, got {len(matches)}')
    return int(matches[0])

def source_map(directory):
    paths = sp.check_output(['git','-C',str(directory),'ls-files','-z']).split(b'\0')
    return {os.fsdecode(p): sha(directory/os.fsdecode(p)) for p in paths
            if p and (directory/os.fsdecode(p)).is_file()}

def integrity():
    m = json.loads((HERE/'manifest.json').read_text())
    failures = []
    for name, directory in [('DMG',ROOT),('EigenScript',EIGS),('ouroboros',OURO)]:
        if source_map(directory) != m['source_content_sha256'][name]:
            failures.append(name+' source content changed')
    for rel, digest in m['files'].items():
        if digest != 'MISSING' and (not (ROOT/rel).is_file() or sha(ROOT/rel) != digest):
            failures.append(rel+' identity changed')
    return failures

def classify(record, arm):
    p = HERE/record['name']
    data = Path(str(p)+'.stdout').read_bytes()
    err = Path(str(p)+'.stderr').read_bytes()
    expected = HERE/f'correctness/parity/{arm}-500000'
    reasons = integrity()
    if record['exit_status'] != 0:
        reasons.append('timeout' if record['timeout'] else 'nonzero exit')
    if norm(data) != norm(Path(str(expected)+'.stdout').read_bytes()):
        reasons.append('normalized stdout mismatch')
    if err != Path(str(expected)+'.stderr').read_bytes():
        reasons.append('stderr mismatch')
    try:
        actual = cycles(data)
        if actual != cycles(Path(str(expected)+'.stdout').read_bytes()) or actual < 500000:
            reasons.append('unexpected/short cycle count')
    except ValueError as e:
        actual = None
        reasons.append(str(e))
    wall = record['elapsed_ns']/1e9
    child_cpu = record['child_user_s']+record['child_system_s']
    excess = max(0, busy_seconds(record['before'],record['after'])-child_cpu)/wall
    temps = [int(v) for snap in ('before','after') for k,v in record[snap].items()
             if k.endswith('/temp') and v.strip().isdigit()]
    if max(temps,default=0) >= 70000:
        reasons.append('temperature >=70 C')
    if excess > .50:
        reasons.append('excess host busy CPU >0.50 CPU-equivalents')
    record.update(actual_cycles=actual, valid=not reasons, exclusion_reasons=reasons,
                  excess_host_busy_cpu_equivalents=excess,
                  wall_seconds=wall, mhz=actual/wall/1e6 if actual and not reasons else None)
    write(Path(str(p)+'.json'),record)

def build():
    for name, cmd, extra in [
        ('runtime', ['make', '-C', EIGS, 'CC=gcc'], {}),
        ('native-dmg', ['bash', OURO/'aot/build.sh', ROOT/'dmg.eigs', AOT],
         {'EIGS_DIR': str(EIGS), 'EIGS': str(VM)}),
        ('native-cpu', ['bash', OURO/'aot/build.sh', ROOT/'tests/test_cpu.eigs', BUILD/'test_cpu-aot'],
         {'EIGS_DIR': str(EIGS), 'EIGS': str(VM)}),
        ('native-memory', ['bash', OURO/'aot/build.sh', ROOT/'tests/test_memory.eigs', BUILD/'test_memory-aot'],
         {'EIGS_DIR': str(EIGS), 'EIGS': str(VM)})]:
        r = run('build/'+name, cmd, seconds=1800, envextra=extra)
        if r['exit_status'] and name in ('runtime', 'native-dmg'):
            break

def seal():
    def output(cmd):
        r = sp.run(cmd, text=True, stdout=sp.PIPE, stderr=sp.STDOUT)
        return {'command': cmd, 'exit_status': r.returncode, 'output': r.stdout}
    files = [ROOT/'dmg.eigs', ROOT/'.devcontainer/Dockerfile',
             OURO/'.devcontainer/Dockerfile', OURO/'aot/build.sh',
             OURO/'aot/k_oracle.sh', OURO/'aot/k_budget.txt', EIGS/'Makefile',
             VM, AOT, BUILD/'test_cpu-aot', BUILD/'test_memory-aot', ROM,
             HERE/'PROTOCOL.md', HERE/'experiment.py', HERE/'capture_runtime.py',
             HERE/'capture-runtime.sh', HERE/'handoff-evidence.txt', HERE/'COMMANDS.md']
    files += [HERE/'calibrate.py', HERE/'summarize.py', HERE/'REVIEW.md']
    manifest = dict(frozen_utc=utc(), sources={}, files={}, source_content_sha256={},
                    pins={'DMG': 'v0.48.0', 'ouroboros': 'v0.48.0',
                          'resolved_EigenScript': '546848c0a7123ea7066923ebadb06f0af29af953'},
                    host=host(), memory_limit_KiB=1500000,
                    clock=vars(time.get_clock_info('perf_counter')),
                    sampling_policy='PROTOCOL.md',
                    sanitized_inherited_variable_names=sorted(set(os.environ)-set(cleanenv())))
    for name, p in [('DMG', ROOT), ('EigenScript', EIGS), ('ouroboros', OURO)]:
        manifest['sources'][name] = output(['git', '-C', str(p), 'rev-parse', 'HEAD'])
        manifest['sources'][name]['status'] = output(['git','-C',str(p),'status','--short'])
        manifest['source_content_sha256'][name] = source_map(p)
    for p in files:
        manifest['files'][str(p.relative_to(ROOT))] = sha(p) if p.is_file() else 'MISSING'
    for name, cmd in [('host', ['uname','-a']), ('cpu',['lscpu']),
                      ('os',['cat','/etc/os-release']),
                      ('model',['cat','/sys/class/dmi/id/product_name']),
                      ('virtualization',['systemd-detect-virt']),
                      ('compiler',['gcc','--version']), ('libc',['ldd','--version']),
                      ('vm_symbols',['nm','-D',str(VM)]), ('vm_libraries',['ldd',str(VM)]),
                      ('aot_symbols',['nm','-D',str(AOT)]), ('aot_libraries',['ldd',str(AOT)]),
                      ('perf_access',['perf','stat','-e','instructions,cycles','-x,','/bin/true'])]:
        manifest[name] = output(cmd)
    path = HERE/'manifest.json'
    if path.exists():
        raise RuntimeError('manifest already sealed')
    write(path, manifest)
    (HERE/'manifest.sha256').write_text(sha(path)+'  manifest.json\n')
    print('MANIFEST SEALED', flush=True)

def correct():
    assert (HERE/'manifest.json').is_file()
    summary = {}
    for arm in ('interpreter', 'jit', 'aot'):
        results = []
        if arm != 'aot':
            run(f'correctness/{arm}/jit-diagnostic',
                [VM,ROOT/'dmg.eigs',ROM,'--cycles','500000'],arm,
                envextra={'EIGS_JIT_STATS':'1'})
        for unit in ('cpu', 'memory'):
            cmd = [BUILD/f'test_{unit}-aot'] if arm == 'aot' else [VM, ROOT/f'tests/test_{unit}.eigs']
            if not Path(cmd[0]).is_file():
                results.append({'exit_status': None, 'missing': str(cmd[0])})
                continue
            results.append(run(f'correctness/{arm}/unit-{unit}', cmd, arm))
        if (AOT if arm == 'aot' else VM).is_file():
            extra = {'EIGENSCRIPT': str(HERE/'capture-runtime.sh'),
                     'RECEIPT_ARM': arm}
            for gate in ('cpu_instrs', 'timing'):
                results.append(run(f'correctness/{arm}/blargg-{gate}',
                                   ['bash', ROOT/f'tests/run_blargg_{gate}_suite.sh'],
                                   arm, seconds=12000, envextra=extra))
        summary[arm] = {'gates_ok': len(results) == 4 and all(r['exit_status'] == 0 for r in results),
                        'results': [{'name':r.get('name'), 'exit_status':r['exit_status']} for r in results]}
        write(HERE/'correctness/gates.json', summary)

def parity():
    verdict = {'comparisons': [], 'all_ok': True, 'vm_jit_ok': True, 'vm_aot_ok': True}
    for n, dump in [(0,False), (500000,False), (2000000,False),
                    (500000,True), (2000000,True)]:
        points = {}
        for arm in ('interpreter','jit','aot'):
            cmd = [AOT] if arm == 'aot' else [VM, ROOT/'dmg.eigs']
            cmd += [ROM, '--cycles', str(n)] + (['--dump-state'] if dump else [])
            tag = f'correctness/parity/{arm}-{n}'+('-dump' if dump else '')
            r = run(tag, cmd, arm)
            p = HERE/tag
            data = Path(str(p)+'.stdout').read_bytes()
            err = Path(str(p)+'.stderr').read_bytes()
            Path(str(p)+'.normalized').write_bytes(norm(data))
            points[arm] = (r['exit_status'], norm(data), err)
        ok = points['interpreter'][0] == 0 and len(set(points.values())) == 1
        vm_jit_ok = points['interpreter'][0] == 0 and points['interpreter'] == points['jit']
        vm_aot_ok = points['interpreter'][0] == 0 and points['interpreter'] == points['aot']
        verdict['comparisons'].append({'requested_cycles':n, 'dump_state':dump,
                                       'byte_exact_status_stdout_stderr':ok,
                                       'vm_jit_ok':vm_jit_ok,'vm_aot_ok':vm_aot_ok})
        verdict['all_ok'] &= ok
        verdict['vm_jit_ok'] &= vm_jit_ok
        verdict['vm_aot_ok'] &= vm_aot_ok
    write(HERE/'correctness/parity.json', verdict)

def quiet():
    a = host()
    time.sleep(10)
    b = host()
    busy = busy_seconds(a,b)/10
    temps = [int(v) for k,v in b.items() if k.endswith('/temp') and v.strip().isdigit()]
    ok = busy <= .25 and max(temps, default=0) < 60000
    path = HERE/'quiet-checks.jsonl'
    with path.open('a') as f:
        f.write(json.dumps({'before':a, 'after':b, 'busy_cpu_equivalents':busy, 'ok':ok})+'\n')
    print(f'quiet check: {busy:.3f} busy CPU-equivalents, ok={ok}', flush=True)
    return ok

def busy_seconds(a,b):
    def fields(h):
        v = list(map(int, h['/proc/stat'].splitlines()[0].split()[1:9]))
        return sum(v)-v[3]-v[4]
    return (fields(b)-fields(a))/os.sysconf('SC_CLK_TCK')

def measure():
    gates = json.loads((HERE/'correctness/gates.json').read_text())
    parity_ok = json.loads((HERE/'correctness/parity.json').read_text())['vm_jit_ok']
    if not parity_ok:
        raise RuntimeError('parity failed; no measurements')
    assert not integrity(), integrity()
    manifest = json.loads((HERE/'manifest.json').read_text())
    for p in (VM,ROM):
        assert sha(p) == manifest['files'][str(p.relative_to(ROOT))]
    symbols = manifest['vm_symbols']['output'] + manifest['vm_libraries']['output']
    assert not re.search('__asan|__ubsan|libasan|libubsan', symbols)
    allowed = [a for a in ('interpreter','jit') if gates[a]['gates_ok']]
    for arm in allowed:
        r = run('warmup/'+arm, [VM,ROOT/'dmg.eigs',ROM,'--cycles','500000'],arm)
        classify(r,arm)
        if not r['valid']:
            raise RuntimeError('warmup invalid; no replacements or timing')
    while not quiet():
        time.sleep(10)
    for rep in range(1,8):
        order = ['interpreter','jit','jit-repeat'] if rep % 2 else ['jit-repeat','jit','interpreter']
        for label in order:
            arm = 'jit' if label == 'jit-repeat' else label
            if arm not in allowed:
                continue
            assert not integrity(), integrity()
            r = run(f'samples/{rep:02d}-{label}', [VM,ROOT/'dmg.eigs',ROM,'--cycles','500000'],arm)
            classify(r,arm)

def oracle():
    assert (HERE/'manifest.json').is_file()
    assert not integrity(), integrity()
    # A refused capability probe permits recording the actual oracle refusal.
    # A runnable oracle needs a separate raw-point retention adapter first;
    # do not let its EXIT cleanup erase primary evidence.
    m = json.loads((HERE/'manifest.json').read_text())
    if m['perf_access']['exit_status'] == 0:
        raise RuntimeError('AOT blocked: raw-point retention adapter required before runnable oracle')
    run('aot-oracle/attempt', ['bash',OURO/'aot/k_oracle.sh'], seconds=12000,
        envextra={'DMG_DIR':str(ROOT), 'K_BIN':str(HERE/'aot-oracle/MEASUREMENT_DISABLED'), 'K_REPS':'7',
                  'EIGS_DIR':str(EIGS), 'EIGS':str(VM)})

if __name__ == '__main__':
    resource.setrlimit(resource.RLIMIT_AS, (LIMIT,LIMIT))
    {'build':build,'seal':seal,'correct':correct,'parity':parity,
     'measure':measure,'oracle':oracle}[sys.argv[1]]()
