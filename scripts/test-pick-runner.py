"""Exercise the exact inline workflow script, optionally with live read-only APIs."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

workflow = Path('.github/workflows/pick-runner.yml').read_text()
script = '\n'.join(line[10:] for line in workflow.split('        run: |\n', 1)[1].splitlines())

def item(sku, quantity, repo='private', unit='Minutes'):
    return dict(product='actions', unitType=unit, repositoryName=repo, sku=sku, quantity=quantity)

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    (root / 'pick.sh').write_text(script)
    fake = root / 'gh'
    fake.write_text('''#!/bin/bash
if [[ "$FAIL_API" == 1 ]]; then exit 1; fi
if [[ "$FAIL_API" == repos && "$*" == *'/repos?'* ]]; then exit 1; fi
if [[ "$*" == *'/repos?'* ]]; then cat "$FIXTURE/repos.json"; else cat "$FIXTURE/usage.json"; fi
''')
    fake.chmod(0o700)
    env = dict(os.environ, PATH=f'{root}:{os.environ["PATH"]}', FIXTURE=str(root),
               GH_TOKEN='fixture-placeholder', ORG='AgentsKit-io', MIN_REMAINING='100',
               INCLUDED_MINUTES='2000', VARIANT='', FORCE_RUNNER='', FAIL_API='0',
               GITHUB_STEP_SUMMARY=str(root / 'summary'), GITHUB_OUTPUT=str(root / 'output'))
    repos = [[dict(name='private', private=True)]]
    usage = [dict(usageItems=[item('Actions Linux', 100), item('Actions Windows', 100),
                            item('Actions macOS 3-core', 10), item('Future SKU', 1),
                            item('Actions Linux', 9000, 'public'),
                            item('Actions storage', 9000, unit='GigabyteHours')])]

    def run(name, expected, **overrides):
        (root / 'output').write_text('')
        (root / 'summary').write_text('')
        result = subprocess.run(['bash', str(root / 'pick.sh')], env=dict(env, **overrides),
                                capture_output=True, text=True, check=True)
        assert f'runner={expected};' in result.stdout, result.stdout
        output = (root / 'output').read_text().splitlines()
        assert output[0].startswith('runner<<') and output[1] == expected
        assert output[0][8:] == output[2]
        assert f'runner={expected};' in (root / 'summary').read_text()
        print(f'{name}:\n{result.stdout}', end='')
        return result.stdout

    def fixtures():
        (root / 'repos.json').write_text(json.dumps(repos))
        (root / 'usage.json').write_text(json.dumps(usage))

    fixtures()
    assert 'used=401; remaining=1599;' in run('weighted/public/storage/unknown', 'ubuntu-latest')
    run('arm', 'ubuntu-24.04-arm', VARIANT='arm')
    run('threshold equality', 'depot-ubuntu-24.04', MIN_REMAINING='1599')
    usage = [dict(usageItems=[item('Actions Linux', 2001)])]
    fixtures()
    run('exhausted fixture', 'depot-ubuntu-24.04')
    run('API failure fixture', 'depot-ubuntu-24.04', FAIL_API='1')
    run('repository API failure', 'depot-ubuntu-24.04', FAIL_API='repos')
    run('missing token', 'depot-ubuntu-24.04', GH_TOKEN='')
    run('force precedes larger variant/API', 'custom-runner', FORCE_RUNNER='custom-runner', VARIANT='8', FAIL_API='1')
    for variant in ('4', '8'):
        run(f'larger {variant}', f'depot-ubuntu-24.04-{variant}', VARIANT=variant, FAIL_API='1')
    (root / 'usage.json').write_text('invalid json')
    run('malformed response', 'depot-ubuntu-24.04')
    if '--live' in sys.argv:
        # gh uses its existing credential store; no credential is extracted or printed.
        import datetime
        now = datetime.datetime.now(datetime.timezone.utc)
        real_env = {k: v for k, v in os.environ.items() if k != 'GH_TOKEN'}
        for endpoint, filename in (
            (f'/organizations/AgentsKit-io/settings/billing/usage?year={now.year}&month={now.month}', 'usage.json'),
            ('/orgs/AgentsKit-io/repos?type=private&per_page=100', 'repos.json'),
        ):
            response = subprocess.run(['gh', 'api', '--paginate', '--slurp', '-H',
                                       'X-GitHub-Api-Version: 2022-11-28', endpoint],
                                      env=real_env, capture_output=True, check=True)
            (root / filename).write_bytes(response.stdout)
        result = subprocess.run(['bash', str(root / 'pick.sh')], env=env,
                                capture_output=True, text=True, check=True)
        assert 'reason=included minutes' in result.stdout, result.stdout
        print(f'live API snapshot ({now.isoformat()}):\n{result.stdout}', end='')
