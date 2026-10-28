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
               INCLUDED_MINUTES='2000', VARIANT='', FORCE_RUNNER='', FAIL_API='0', REPO_PRIVATE='true',
               FALLBACK_RUNNER='', CACHED_REMAINING='', CACHED_AT='',
               GITHUB_STEP_SUMMARY=str(root / 'summary'), GITHUB_OUTPUT=str(root / 'output'))
    repos = [[dict(name='private', private=True)]]
    usage = [dict(usageItems=[item('Actions Linux', 100), item('Actions Windows', 100),
                            item('Actions macOS 3-core', 10), item('Future SKU', 1),
                            item('Actions Linux', 9000, 'public'),
                            item('Actions storage', 9000, unit='GigabyteHours')])]

    def run(name, expected, runs_on=None, **overrides):
        (root / 'output').write_text('')
        (root / 'summary').write_text('')
        result = subprocess.run(['bash', str(root / 'pick.sh')], env=dict(env, **overrides),
                                capture_output=True, text=True, check=True)
        assert f'runner={expected};' in result.stdout, result.stdout
        output = (root / 'output').read_text().splitlines()
        assert output[0].startswith('runner<<') and output[1] == expected
        assert output[0][8:] == output[2]
        # runs_on is always JSON: the label quoted, or the fallback as given.
        assert output[3].startswith('runs_on<<') and output[3][9:] == output[5]
        assert json.loads(output[4]) == json.loads(runs_on if runs_on is not None else json.dumps(expected)), output[4]
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
    # Public repositories never use Depot, whatever the billing data says; force still wins.
    run('public repository', 'ubuntu-latest', REPO_PRIVATE='false', FAIL_API='1')
    run('public arm', 'ubuntu-24.04-arm', REPO_PRIVATE='false', VARIANT='arm')
    for variant in ('4', '8'):
        run(f'public larger {variant}', 'ubuntu-latest', REPO_PRIVATE='false', VARIANT=variant)
    run('public forced', 'custom-runner', REPO_PRIVATE='false', FORCE_RUNNER='custom-runner')
    run('unknown visibility uses the private rules', 'depot-ubuntu-24.04', REPO_PRIVATE='', FAIL_API='1')
    (root / 'usage.json').write_text('invalid json')
    run('malformed response', 'depot-ubuntu-24.04')

    # Organizations without Depot: fallback_runner (JSON) replaces Depot; a cached remaining count can stand in
    # for the billing API when there is no token.
    import datetime
    now = datetime.datetime.now(datetime.timezone.utc)
    fresh = now.strftime('%Y-%m-%dT%H:%M:%SZ')
    fb = '["self-hosted","docker"]'
    cache = dict(GH_TOKEN='', FALLBACK_RUNNER=fb, CACHED_AT=fresh)
    run('cache above threshold', 'ubuntu-latest', CACHED_REMAINING='500', **cache)
    assert 'used=1500; remaining=500;' in run('cache arm', 'ubuntu-24.04-arm', CACHED_REMAINING='500', VARIANT='arm', **cache)
    run('cache at threshold', fb, fb, CACHED_REMAINING='100', **cache)
    run('cache exhausted (negative)', fb, fb, CACHED_REMAINING='-211', **cache)
    run('cache not a number', fb, fb, CACHED_REMAINING='lots', **cache)
    stale = (now - datetime.timedelta(hours=37)).strftime('%Y-%m-%dT%H:%M:%SZ')
    run('stale cache', fb, fb, CACHED_REMAINING='1999', **dict(cache, CACHED_AT=stale))
    last_month = (now.replace(day=1) - datetime.timedelta(minutes=1)).strftime('%Y-%m-%dT%H:%M:%SZ')
    run('cache from last month', fb, fb, CACHED_REMAINING='1999', **dict(cache, CACHED_AT=last_month))
    run('cache without timestamp', fb, fb, CACHED_REMAINING='1999', **dict(cache, CACHED_AT=''))
    run('fractional-second timestamp', 'ubuntu-latest', CACHED_REMAINING='500',
        **dict(cache, CACHED_AT=now.strftime('%Y-%m-%dT%H:%M:%S.123Z')))
    run('fallback, no token, no cache', fb, fb, **dict(cache, CACHED_AT=''))
    run('fallback string label', '"factory"', '"factory"', CACHED_REMAINING='0', **dict(cache, FALLBACK_RUNNER='"factory"'))
    run('fallback, larger variant does not need Depot', fb, fb, CACHED_REMAINING='0', VARIANT='8', **cache)
    run('fallback public repository', 'ubuntu-latest', REPO_PRIVATE='false', **cache)
    run('fallback forced', 'custom-runner', FORCE_RUNNER='custom-runner', **cache)
    # A token wins over the cache: live billing decides.
    usage = [dict(usageItems=[item('Actions Linux', 2001)])]
    fixtures()
    run('fallback, billing exhausted', fb, fb, FALLBACK_RUNNER=fb, CACHED_REMAINING='1999', CACHED_AT=fresh)
    run('fallback, billing API failure', fb, fb, FALLBACK_RUNNER=fb, FAIL_API='1')
    usage = [dict(usageItems=[item('Actions Linux', 10)])]
    fixtures()
    run('fallback, billing has minutes', 'ubuntu-latest', FALLBACK_RUNNER=fb)
    bad = subprocess.run(['bash', str(root / 'pick.sh')], env=dict(env, FALLBACK_RUNNER='self-hosted,docker'),
                         capture_output=True, text=True)
    assert bad.returncode != 0 and 'fallback_runner must be a JSON' in bad.stdout, bad.stdout
    print('invalid fallback_runner: rejected')
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
