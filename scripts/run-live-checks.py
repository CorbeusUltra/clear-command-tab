"""Run the opt-in signed GUI test host and propagate its explicit result."""
from pathlib import Path
import json
import subprocess
import sys
import uuid

host, report = (Path(value).resolve() for value in sys.argv[1:3])
report.parent.mkdir(parents=True, exist_ok=True)
run_report = report.with_name(f'{report.stem}-{uuid.uuid4().hex}.json')
root = Path(__file__).resolve().parent.parent
registrar = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
try:
    subprocess.run(['/usr/bin/open', '-n', '-W', str(host), '--args', str(run_report), str(root)], check=True, timeout=90)
finally:
    subprocess.run([registrar, '-u', str(host)], check=True, stdout=subprocess.DEVNULL)
if not run_report.exists():
    raise SystemExit('FAIL: test host produced no report')
result = json.loads(run_report.read_text())
report.write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
raise SystemExit({'passed': 0, 'skipped': 77}.get(result.get('status'), 1))
