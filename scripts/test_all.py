#!/usr/bin/env python3
"""Run offline Netmin fixtures without launching or replacing an app bundle."""
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import argparse
import json
import os
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def run_suites(root, logs, jobs=2, *, scripts=None, environment=None):
    root, logs = Path(root), Path(logs)
    logs.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update(environment or {})
    env.setdefault('DEVELOPER_DIR', '/Applications/Xcode.app/Contents/Developer')
    scripts = scripts if scripts is not None else sorted((root / 'scripts').glob('test_*.py'))
    tasks = [(path.stem, [sys.executable, str(path)]) for path in scripts if path.name != 'test_all.py']

    def run(task):
        name, command = task
        with (logs / (name + '.log')).open('w') as output:
            try:
                result = subprocess.run(command, cwd=root, env=env, stdout=output,
                                        stderr=subprocess.STDOUT, timeout=300)
                return name, result.returncode
            except subprocess.TimeoutExpired:
                output.write('\nSuite exceeded its five-minute limit.\n')
                return name, 124

    results = {}
    with ThreadPoolExecutor(max_workers=jobs) as executor:
        for future in as_completed([executor.submit(run, task) for task in tasks]):
            name, code = future.result()
            results[name] = code
            print(f'{"PASS" if code == 0 else "FAIL"} {name}', flush=True)
    (logs / 'results.json').write_text(json.dumps(results, indent=2, sort_keys=True) + '\n')
    passed = sum(code == 0 for code in results.values())
    print(f'{passed}/{len(results)} suites passed. Logs: {logs}', flush=True)
    return 0 if passed == len(results) else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--logs', type=Path)
    parser.add_argument('--jobs', type=int, choices=range(1, 5), default=2)
    args = parser.parse_args()
    logs = args.logs or Path(tempfile.mkdtemp(prefix='netmin-checks-', dir='/private/tmp'))
    sys.exit(run_suites(ROOT, logs, args.jobs))
