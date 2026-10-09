#!/usr/bin/env python3
"""Exercise generated rules against simulated commands; never touch the host firewall."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

MOCK = r'''#!/usr/bin/env python3
import json, os, shlex, subprocess, sys
from pathlib import Path
path = Path(os.environ['RULE_STATE'])
state = json.loads(path.read_text())
tool = Path(sys.argv[0]).name
args = sys.argv[1:]
if tool in ('iptables-restore', 'ip6tables-restore'):
    assert '--noflush' in args
    target = tool.removesuffix('-restore')
    table = None
    for line in sys.stdin.read().splitlines():
        if line.startswith('*'): table = line[1:]
        elif line == 'COMMIT': pass
        elif line.strip():
            result = subprocess.run([str(Path(sys.argv[0]).with_name(target)), '-t', table, *shlex.split(line)])
            if result.returncode: sys.exit(result.returncode)
    sys.exit(0)
command = tool + ' ' + ' '.join(args)
fail = os.environ.get('FAIL_PATTERN')
if fail and fail in command and not state.get('failed'):
    state['failed'] = True
    path.write_text(json.dumps(state))
    print('simulated failure: ' + command, file=sys.stderr)
    sys.exit(1)
code = 0
if tool in ('iptables', 'ip6tables'):
    args = args[2:] if args[:1] == ['-w'] else args
    assert args[0] == '-t'
    table = args[1]
    if args[2:] == ['-S']:
        print('table available'); sys.exit(0)
    action, chain = args[2:4]
    rest = args[4:]
    chains = state['chains'][tool + ':' + table]
    if action == '-N':
        if chain in chains: code = 1
        else: chains[chain] = []
    elif action == '-S':
        if chain not in chains: code = 1
        else: print('\n'.join(' '.join(rule) for rule in chains[chain]))
    elif action in ('-A', '-I'):
        if chain not in chains: code = 1
        else:
            if action == '-I':
                if rest and rest[0].isdigit(): rest = rest[1:]
                chains[chain].insert(0, rest)
            else: chains[chain].append(rest)
    elif action == '-C': code = int(chain not in chains or rest not in chains[chain])
    elif action == '-D':
        if chain not in chains or rest not in chains[chain]: code = 1
        else: chains[chain].remove(rest)
    elif action == '-F':
        # Global flush or deleting another application's chain is an error in this test.
        assert chain.startswith('MCLASH_R_'), command
        if chain not in chains: code = 1
        else: chains[chain].clear()
    elif action == '-X':
        assert chain.startswith('MCLASH_R_'), command
        if chain not in chains or chains[chain] or any(['-j', chain] == r[-2:] for rs in chains.values() for r in rs): code = 1
        else: del chains[chain]
    else: raise AssertionError(command)
elif tool == 'ip':
    assert args[0] in ('-4', '-6')
    family = '6' if args[0] == '-6' else ''
    rule_key, route_key = 'rules' + family, 'routes' + family
    kind, action = args[1:3]
    if kind == 'rule' and action == 'show':
        for r in state[rule_key]: print(r)
    elif kind == 'route' and action == 'show':
        assert args[3] == 'table'
        for r in state[route_key]:
            if r[-1] == args[4]: print(' '.join(r))
    elif kind == 'route':
        route = args[3:]
        assert action in ('add', 'del')
        if action == 'add':
            if route in state[route_key]: code = 1
            else: state[route_key].append(route)
        elif route not in state[route_key]: code = 1
        else: state[route_key].remove(route)
    elif kind == 'rule':
        spec = args[3:]
        assert spec[0] == 'pref'
        rule = spec[1] + ': from all ' + ' '.join(spec[2:])
        if action == 'add': state[rule_key].append(rule)
        elif action == 'del':
            if rule not in state[rule_key]: code = 1
            else: state[rule_key].remove(rule)
        else: raise AssertionError(command)
    else: raise AssertionError(command)
else: raise AssertionError(command)
path.write_text(json.dumps(state))
sys.exit(code)
'''


def initial():
    return {
        'chains': {
            'iptables:mangle': {'OUTPUT': [['-j', 'ANDROID_SYSTEM']], 'PREROUTING': [['-j', 'FOREIGN_PROXY']], 'ANDROID_SYSTEM': [], 'FOREIGN_PROXY': []},
            'iptables:nat': {'OUTPUT': [['-j', 'ANDROID_DNS']], 'PREROUTING': [], 'ANDROID_DNS': []},
            'ip6tables:mangle': {'OUTPUT': [['-j', 'ANDROID_SYSTEM6']], 'PREROUTING': [['-j', 'FOREIGN_PROXY6']], 'ANDROID_SYSTEM6': [], 'FOREIGN_PROXY6': []},
            'ip6tables:nat': {'OUTPUT': [['-j', 'ANDROID_DNS6']], 'PREROUTING': [], 'ANDROID_DNS6': []},
            'ip6tables:filter': {'OUTPUT': [['-j', 'ANDROID_V6']], 'FORWARD': [], 'ANDROID_V6': []},
        },
        'rules6': ['10000: from all lookup 123'],
        'routes6': [['2001:db8::/64', 'dev', 'eth0', 'table', '123']],
        'rules': ['10000: from all lookup 123'],
        'routes': [['203.0.113.0/24', 'dev', 'eth0', 'table', '123']],
    }


def main(install, cleanup, hotspot=None):
    with tempfile.TemporaryDirectory() as temporary:
        directory = Path(temporary)
        for name in ('iptables', 'ip6tables', 'ip', 'iptables-restore', 'ip6tables-restore'):
            tool = directory / name
            tool.write_text(MOCK)
            tool.chmod(0o755)
        environment = dict(os.environ, PATH=str(directory) + os.pathsep + os.environ['PATH'], RULE_STATE=str(directory / 'state.json'))
        def run(script, fail=None):
            env = dict(environment)
            if fail: env['FAIL_PATTERN'] = fail
            result = subprocess.run(['/bin/sh', str(script)], env=env, capture_output=True, text=True, timeout=40)
            return result
        state_file = directory / 'state.json'
        failures = [None,
                    'iptables -w 5 -t mangle -N MCLASH_R_PRE',
                    'ip6tables -w 5 -t filter -N MCLASH_R_V6',
                    'iptables -w 5 -t mangle -A MCLASH_R_PRE -p udp -j TPROXY',
                    'ip -4 route add', 'ip -4 rule add',
                    'iptables -w 5 -t nat -I OUTPUT',
                    'iptables -w 5 -t nat -N MCLASH_R_HDNS',
                    'ip6tables -w 5 -t filter -I FORWARD',
                    'ip6tables -w 5 -t filter -I OUTPUT',
                    'iptables -w 5 -t mangle -A OUTPUT -j MCLASH_R_OUT']
        dual_stack = 'ip6tables -w 5 -t mangle -N MCLASH_R_OUT6' in install.read_text()
        if dual_stack:
            failures += ['ip6tables -w 5 -t mangle -N MCLASH_R_OUT6',
                         'ip6tables -w 5 -t mangle -N MCLASH_R_DNS6',
                         'ip6tables -w 5 -t mangle -A MCLASH_R_PRE6 -p udp -j TPROXY',
                         'ip -6 route add', 'ip -6 rule add',
                         'ip6tables -w 5 -t mangle -A MCLASH_R_OUT6 -j MCLASH_R_DNS6',
                         'ip6tables -w 5 -t mangle -A OUTPUT -j MCLASH_R_OUT6',
                         'ip6tables -w 5 -t mangle -N MCLASH_R_HDNS6']
        for failure in failures:
            before = initial()
            state_file.write_text(json.dumps(before))
            result = run(install, failure)
            assert (result.returncode == 0) == (failure is None), (failure, result.stdout, result.stderr)
            if failure is None and hotspot is not None:
                result = run(hotspot)
                assert result.returncode == 0, (result.stdout, result.stderr)
                installed = json.loads(state_file.read_text())['chains']
                for key, chain in (('iptables:mangle', 'MCLASH_R_HOT'),
                                   ('iptables:nat', 'MCLASH_R_HDNS'),
                                   ('ip6tables:filter', 'MCLASH_R_HV6')):
                    assert installed[key][chain] or (dual_stack and chain == 'MCLASH_R_HV6'), (key, chain)
                if dual_stack:
                    assert installed['ip6tables:mangle']['MCLASH_R_HOT6']
                    assert installed['ip6tables:mangle']['MCLASH_R_HDNS6']
            result = run(cleanup)
            assert result.returncode == 0, (result.stdout, result.stderr)
            after = json.loads(state_file.read_text())
            after.pop('failed', None)
            assert after == before, (failure, after)
            # A second cleanup must succeed without changing any foreign state.
            assert run(cleanup).returncode == 0
            repeated = json.loads(state_file.read_text())
            repeated.pop('failed', None)
            assert repeated == after
        for collision in ('priority', 'table'):
            before = initial()
            if collision == 'priority': before['rules'].append('9000: from all lookup 456')
            else: before['routes'].append(['local', '0.0.0.0/0', 'dev', 'lo', 'table', '20230'])
            state_file.write_text(json.dumps(before))
            assert run(install).returncode != 0
            assert run(cleanup).returncode == 0
            assert json.loads(state_file.read_text()) == before
        if dual_stack:
            for collision in ('priority', 'table'):
                before = initial()
                if collision == 'priority': before['rules6'].append('9000: from all lookup 456')
                else: before['routes6'].append(['local', '::/0', 'dev', 'lo', 'table', '20230'])
                state_file.write_text(json.dumps(before))
                assert run(install).returncode != 0
                assert run(cleanup).returncode == 0
                assert json.loads(state_file.read_text()) == before
        print(f'Rule lifecycle passed: hotspot update, normal stop, {len(failures)-1} partial failures, repeat cleanup and 2 foreign collisions.')


if __name__ == '__main__':
    main(Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]) if len(sys.argv) > 3 else None)
