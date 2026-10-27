#!/usr/bin/env python3
"""Free local diagnostics; an explicit --live runs a disposable handoff canary."""
import argparse
import ast
import contextlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile

SOURCE = Path(__file__).resolve().parent
REVISION = '2026-10-10-r1'
# Static protocol clauses from kit v1.0.1. These prove role wiring, not that
# arbitrary customized instructions are semantically safe or will be obeyed.
ROLE_CONTRACTS = {
    'review': ['# Review profile', 'You are **read-only**: no edits, no commits, no branch changes, no installs, no\npushes.', '''=== HANDOFF REVIEW ===
brief-revision: <echoed from the brief's revision: frontmatter>
repo: <basename of the working directory>   branch: <actual current branch>   tree: clean | <n> modified
lenses: does-it-run, claim-by-claim, premise-and-scope
verified: <n> attacked, <n> dropped
verdict: RUN | REVISE | REWRITE
--- FINDINGS ---
[BLOCKER|WRONG|MISSING|RISK|SCOPE] <one line>
  claim:    "<quoted from the brief>"
  actual:   <what the repo shows>
  evidence: <command run, or path:line>
  fix:      <what the brief should say instead>
--- UNVERIFIABLE ---
- <claim> — needs <write|network|credential>, not checked
--- MISSING FROM BRIEF ---
- <what the runner would have to guess>
=== END HANDOFF REVIEW ==='''],
    'run': ['# Run profile', 'End with the completion report exactly as your prompt defines it:',
            '`outcome: COMPLETE` only when every Done-when holds and the report\'s not-done section is\nempty.'],
    'close': ['# Close profile', 'You are **read-only**: no edits, no commits, no branch changes, no installs, no pushes.',
              'End with the audit block exactly as your prompt defines it, and nothing after it.'],
}


class CheckError(Exception):
    pass


class CommandFailed(CheckError):
    pass


def require(condition, why):
    if not condition:
        raise CheckError(why)


def run(args, cwd, env, timeout=60, log=None, allow_unset=False, stdout_only=False):
    """Bounded foreground commands, killing the whole process group on timeout."""
    with contextlib.ExitStack() as stack:
        # Reserve before running any child: a late symlink cannot redirect writes.
        stream = stack.enter_context(log.open('x', encoding='utf-8')) if log is not None else None
        with subprocess.Popen(args, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE if stdout_only else subprocess.STDOUT,
                              text=True, start_new_session=True) as proc:
            try:
                out, err = proc.communicate(timeout=timeout)
            except (subprocess.TimeoutExpired, KeyboardInterrupt):
                os.killpg(proc.pid, signal.SIGKILL)
                out, _ = proc.communicate()
                if stream is not None:
                    stream.write(out)
                raise CheckError('command timed out or interrupted: ' + Path(args[0]).name)
        if stream is not None:
            stream.write(out)
    # Agent output can contain credentials. Keep it in private launcher artifacts,
    # never interpolate it into diagnostic messages or reports.
    if proc.returncode != 0:
        if allow_unset and 'Config key not set' in out + (err or ''):
            return 'null'
        raise CommandFailed('%s exited %s (inspect private fixture logs)' % (Path(args[0]).name, proc.returncode))
    return out


def git_environment(env):
    env = {k: v for k, v in env.items() if not k.startswith(('GIT_', 'HERMES_KANBAN_')) and k not in
           ('PYTHONPATH', 'PYTHONHOME', 'PYTHONSTARTUP')}
    env.update(GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull,
               GIT_ALLOW_PROTOCOL='file', GIT_TERMINAL_PROMPT='0',
               GIT_AUTHOR_NAME='Setup canary', GIT_AUTHOR_EMAIL='canary@localhost',
               GIT_COMMITTER_NAME='Setup canary', GIT_COMMITTER_EMAIL='canary@localhost',
               PYTHONDONTWRITEBYTECODE='1')
    return env


def plain_file(path):
    require(path.is_file() and not path.is_symlink(), 'missing, non-regular or symlink file: ' + path.name)
    return path.read_text(encoding='utf-8')


def read_env(path, last=False):
    if not path.exists() and not path.is_symlink():
        return {}
    text = plain_file(path)
    values = {}
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        key, sep, value = line.partition('=')
        require(bool(sep) and re.fullmatch(r'[A-Z_][A-Z_0-9]*', key), 'invalid env syntax in ' + path.name)
        if last or key not in values:
            values[key] = value
    return values


def make_fixture(root, source, env):
    """Never reuse a path or inspect the user's legacy demo repository."""
    root.mkdir(mode=0o700)  # exclusive; dangling symlinks also fail
    repo = root / 'repo'
    shutil.copytree(source / '.seed/demo-repo', repo, symlinks=True)
    for p in repo.iterdir():
        require(not p.is_symlink(), 'symlink in demo seeds')
    run(['git', 'init', '-q', '-b', 'main'], repo, env)
    run(['git', 'add', '.'], repo, env)
    run(['git', '-c', 'commit.gpgsign=false', 'commit', '-qm', 'Initial canary'], repo, env)
    base = run(['git', 'rev-parse', 'HEAD'], repo, env).strip()
    run(['git', 'clone', '-q', '--bare', str(repo), str(root / 'origin.git')], root, env)
    run(['git', 'remote', 'add', 'origin', str(root / 'origin.git')], repo, env)
    run(['git', 'switch', '-qc', 'feat/version-flag'], repo, env)
    notes = root / 'notes'
    sub = notes / '02-projects/example/subprojects/example-version-flag'
    shutil.copytree(source / '.seed/02-projects/example', notes / '02-projects/example')
    defaults = notes / '02-projects/_templates'
    defaults.mkdir()
    shutil.copyfile(source / '.seed/02-projects/_templates/handoff-defaults.yml', defaults / 'handoff-defaults.yml')
    # These are template files, not private notes or the operator's local rules.
    shutil.copyfile(source / 'AGENTS.md', notes / 'AGENTS.md')
    shutil.copytree(source / '.agents', notes / '.agents')
    shutil.copytree(source / '.claude/skills', notes / '.claude/skills')
    (notes / 'AGENTS.local.md').write_text('# Disposable setup canary\nOnly work inside this temporary notes root and its sibling repo. Never contact Telegram, open a PR, install or enable services. Origin is a local-only bare repository.\n')
    (notes / 'brain.env').write_text('DEFAULT_BACKEND=claude\nNOTIFY=\n')
    (notes / '01-daily').mkdir()
    (notes / '05-weekly').mkdir()
    brief = sub / 'specs/2026-10-10-brief-1-version-flag.md'
    for p in sub.rglob('*.md'):
        p.write_text(plain_file(p).replace('@DEMO_REPO@', str(repo)))
    brief.write_text(brief.read_text() + '\nCanary boundary: origin is local-only. Do not create a PR or use external remotes. Never edit the acceptance checker. Leave a clean, committed tree; only hello.py and test_hello.py may change.\n')
    run(['git', 'init', '-q', '-b', 'main'], notes, env)
    run(['git', 'add', '.'], notes, env)
    run(['git', '-c', 'commit.gpgsign=false', 'commit', '-qm', 'Initial isolated notes'], notes, env)
    # Independent external tests are not available for the model to weaken.
    return {'root': root, 'repo': repo, 'notes': notes, 'brief': brief, 'base': base,
            'original_tests': plain_file(repo / 'test_hello.py')}


def block(text, name):
    matches = re.findall(r'^=== ' + re.escape(name) + r' ===\n(.*?)^=== END ' + re.escape(name) + r' ===[ \t]*$', text, re.M | re.S)
    require(len(matches) == 1, 'missing or ambiguous ' + name + ' block')
    return matches[0]


def field(text, key, value):
    require(re.findall(r'^' + re.escape(key) + r':[ \t]*(.*?)[ \t]*$', text, re.M) == [value], 'invalid or ambiguous protocol field ' + key)


def verify_live(f, env):
    repo, brief = f['repo'], f['brief']
    text = plain_file(brief)
    require(text.startswith('---\n') and '\n---\n' in text[4:], 'invalid brief frontmatter')
    fm = text.split('---\n', 2)[1]
    field(fm, 'handoff', 'closed')
    field(fm, 'repo', str(repo))
    field(fm, 'branch', 'feat/version-flag')
    field(fm, 'revision', REVISION)
    review = plain_file(brief.with_suffix('.review.md'))
    reviewed = block(review, 'HANDOFF REVIEW')
    field(reviewed, 'brief-revision', REVISION)
    require(re.findall(r'^verdict: (RUN|REVISE|REWRITE)$', reviewed, re.M) in [['RUN'], ['REVISE']], 'invalid review verdict')
    revise = re.split(r'^## Revise outcome\b[^\n]*$', review, flags=re.M)
    require(len(revise) >= 2, 'missing revise outcome')
    field(revise[-1], 'gate', 'clean')
    report = plain_file(brief.with_suffix('.report.md'))
    completion = block(report, 'COMPLETION REPORT')
    field(completion, 'outcome', 'COMPLETE')
    require(re.search(r'^audit:.*\b0 refuted, 0 unconfirmed[ \t]*$', completion, re.M), 'missing clean completion audit')
    nd = re.findall(r'^--- NOT DONE ---\n(.*?)(?=^--- |\Z)', completion, re.M | re.S)
    require(len(nd) == 1 and nd[0].strip().lower() == '- none', 'NOT DONE is not empty')
    require(re.search(r'^## Debrief outcome\b', report, re.M), 'missing debrief outcome')
    close = block(plain_file(brief.with_suffix('.close.md')), 'CLOSE AUDIT')
    field(close, 'VERDICT', 'PASS')
    done = plain_file(brief.with_suffix('.done-when.md'))
    require(done.startswith('# done-when · '), 'missing structured done-when results')
    for item, command in [(1, 'python3 -m unittest -q'), (2, 'python3 hello.py --version')]:
        require(re.search(r'^§4\.' + str(item) + r' · line \d+ · exit 0 · [^\n]+\n  \$ ' + re.escape(command) + r'$', done, re.M), 'missing successful done-when item ' + str(item))
    require(not re.search(r' · exit (?!0\b)\d+| · not run:', done), 'failed or skipped done-when command')
    require(not run(['git', 'status', '--porcelain', '--untracked-files=all'], repo, env).strip(), 'canary tree is dirty')
    head = run(['git', 'rev-parse', 'HEAD'], repo, env).strip()
    require(head != f['base'], 'no implementation commit')
    run(['git', 'merge-base', '--is-ancestor', f['base'], head], repo, env)
    changed = set(run(['git', 'diff', '--name-only', f['base'], head], repo, env).splitlines())
    require(changed == {'hello.py', 'test_hello.py'}, 'unexpected or missing canary diff')
    for name in changed:
        require(run(['git', 'ls-files', '-s', '--', name], repo, env).startswith('100644 '), 'unexpected file mode')
    require(run(['git', 'remote', 'get-url', 'origin'], repo, env).strip() == str(f['root'] / 'origin.git'), 'canary origin changed')
    # Read code without importing it into the checker process.
    original = ast.parse(f['original_tests'])
    current = ast.parse(plain_file(repo / 'test_hello.py'))
    old_tests = {n.name: ast.dump(n) for n in ast.walk(original) if isinstance(n, ast.FunctionDef) and n.name.startswith('test_')}
    new_tests = {n.name: ast.dump(n) for n in ast.walk(current) if isinstance(n, ast.FunctionDef) and n.name.startswith('test_')}
    require(all(new_tests.get(k) == v for k, v in old_tests.items()), 'original greeting tests changed')
    require(len(new_tests) > len(old_tests), 'no new regression test')
    output = run([sys.executable, '-m', 'unittest', '-v'], repo, env)
    m = re.search(r'Ran (\d+) tests? in', output)
    require(m and int(m.group(1)) >= 3 and re.search(r'^OK$', output, re.M), 'no verified passing regression suite')
    require(run([sys.executable, 'hello.py', '--version'], repo, env) == 'hello 0.1.0\n', 'wrong version behavior')
    require(run([sys.executable, 'hello.py'], repo, env) == 'Hello, world!\n', 'default greeting regressed')
    require(run([sys.executable, 'hello.py', 'Ada'], repo, env) == 'Hello, Ada!\n', 'named greeting regressed')
    # A token new test is not evidence of coverage. The implementation's test suite
    # must detect the original missing flag in a separate, disposable probe.
    with tempfile.TemporaryDirectory(prefix='coverage-', dir=f['root']) as tmp:
        probe = Path(tmp)
        (probe / 'hello.py').write_text(run(['git', 'show', f['base'] + ':hello.py'], repo, env))
        (probe / 'test_hello.py').write_text(plain_file(repo / 'test_hello.py'))
        try:
            run([sys.executable, '-m', 'unittest', '-q'], probe, env)
        except CommandFailed:
            pass
        else:
            raise CheckError('new tests do not detect the missing version flag')
    require(not run(['git', 'status', '--porcelain', '--untracked-files=all'], repo, env).strip(), 'tests dirtied canary tree')
    return head


def launch_live(f, launcher, backend, model, timeout, env):
    cmd = [launcher, 'loop', str(f['brief']), '--gate', 'auto', '--backend', backend]
    if model:
        cmd += ['--model', model]
    env = dict(env, VAULT=str(f['notes']), HANDOFF_DEFAULTS='02-projects/_templates/handoff-defaults.yml', HANDOFF_PROJECTS='02-projects')
    run(cmd, f['notes'], env, timeout, log=f['root'] / 'launcher.log')
    return verify_live(f, env)


def write_backend_shim(f, backend, live=False):
    shim = f['root'] / 'bin' / backend
    if live:
        cli = shutil.which(backend)
        require(cli is not None, 'backend executable missing: ' + backend)
        lines = ['#!/bin/sh', 'export HOME=' + shlex.quote(os.environ['HOME'])]
        for key in ['XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_CACHE_HOME']:
            lines.append('export ' + key + '=' + shlex.quote(os.environ[key]) if key in os.environ else 'unset ' + key)
        lines.append('exec ' + shlex.quote(cli) + ' "$@"')
    else:
        # The pinned Devin launcher probes auth even during --dry-run. Satisfy
        # only that parser prerequisite offline; this is NOT auth evidence.
        lines = ['#!/bin/sh', 'if [ "$1 $2" = "auth status" ]; then echo "logged in (OFFLINE STUB: auth NOT TESTED)"; exit 0; fi',
                 'echo "backend execution denied in free preflight" >&2', 'exit 126']
    require(not shim.is_symlink(), 'backend shim replaced by symlink')
    shim.write_text('\n'.join(lines) + '\n')
    shim.chmod(0o700)


def isolate_launcher_home(f, backend, env):
    """Kit hooks/config stay disposable; the actual CLI keeps its installed auth.

    This is working-directory isolation, NOT a security sandbox for an agent.
    """
    env = dict(env)

    home = f['root'] / 'home'
    home.mkdir(mode=0o700)
    bins = f['root'] / 'bin'
    bins.mkdir()
    write_backend_shim(f, backend)
    # The pinned launcher asks for a PR even for a local origin. Refuse forge calls
    # rather than allow a canary to open a PR. A resulting held run is a real FAIL.
    for name in ['gh', 'glab', 'curl', 'systemctl', 'launchctl', 'loginctl']:
        p = bins / name
        p.write_text('#!/bin/sh\necho "disabled in setup canary" >&2\nexit 126\n')
        p.chmod(0o700)
    env.update(HOME=str(home), PATH=str(bins) + os.pathsep + env['PATH'],
               XDG_CONFIG_HOME=str(home / '.config'), XDG_DATA_HOME=str(home / '.local/share'),
               XDG_CACHE_HOME=str(home / '.cache'))
    # Avoid inherited executable overrides bypassing the backend shim.
    env.pop('CLAUDE_BIN', None)
    env.pop('HERMES_BIN', None)
    env.pop('DEVIN_BIN', None)
    env.pop('CLAUDE_CONFIG_DIR', None)
    env[{'claude': 'CLAUDE_BIN', 'hermes': 'HERMES_BIN', 'devin': 'DEVIN_BIN'}[backend]] = str(bins / backend)
    return env


def backend_diagnostics(brain, backend, record, home=None, hermes=None):
    """Registration evidence only; never run hook strings, auth or model commands.

    Paths/profile selection follow kit v1.0.1, not the active operator profile.
    Config CLI output and exceptions are deliberately never included in reports.
    """
    import datetime

    home = home or Path.home()

    def audit(name, fn):
        try:
            detail = fn()
            if detail is not None:
                record(name, 'PASS', detail)
        except CommandFailed:
            record(name, 'NOT TESTED', 'read-only config query unsupported or failed; values hidden')
        except (CheckError, OSError, ValueError, TypeError, KeyError, AttributeError):
            record(name, 'FAIL', 'missing, malformed, mismatched or stale registration; values hidden')

    def object_file(path):
        data = json.loads(plain_file(path))
        require(isinstance(data, dict), 'expected object')
        return data

    def claude_hooks():
        settings = object_file(brain / '.claude/settings.json')
        local = brain / '.claude/settings.local.json'
        override = object_file(local) if local.exists() or local.is_symlink() else {}
        require(not settings.get('disableAllHooks') and not override.get('disableAllHooks'), 'hooks disabled')
        hooks = settings.get('hooks')
        require(isinstance(hooks, dict), 'missing hooks')
        extra = override.get('hooks', {})
        require(isinstance(extra, dict), 'invalid local hooks')
        # Conservatively audit explicit event overrides too: an empty or divergent
        # override must not be called working wiring based only on the base file.
        expected = [
            ('UserPromptSubmit', None, 'sh "$CLAUDE_PROJECT_DIR/context-guard.sh"', 'context-guard.sh'),
            ('PreToolUse', 'Bash', 'python3 "$CLAUDE_PROJECT_DIR/.claude/hooks/guard-git-refs.py"', '.claude/hooks/guard-git-refs.py'),
            ('Stop', None, 'sh "$(git rev-parse --show-toplevel)/auto-commit.sh"', 'auto-commit.sh'),
        ]
        for event, matcher, command, script in expected:
            plain_file(brain / script)
            for entries in [hooks.get(event)] + ([extra[event]] if event in extra else []):
                require(isinstance(entries, list), 'invalid hook list')
                matches = [h for entry in entries if isinstance(entry, dict) and entry.get('matcher') == matcher
                           for h in entry.get('hooks', []) if isinstance(h, dict) and h.get('type') == 'command' and h.get('command') == command]
                require(len(matches) == 1, 'missing or ambiguous hook')
        return 'context/guard/auto-commit command and matcher registrations + scripts verified; user-scope policy and runtime NOT TESTED'

    if backend == 'claude':
        audit('claude brain hooks', claude_hooks)
    elif backend == 'hermes':
        cli = hermes or shutil.which('hermes')
        expected_homes = {p: home / '.hermes' / 'profiles' / p for p in ['review', 'run', 'close']}
        expected_homes['default'] = home / '.hermes'

        def query(profile, *args):
            require(cli is not None, 'missing hermes')
            return run([cli, '-p', profile, 'config', *args], brain, dict(os.environ), timeout=15,
                       allow_unset=bool(args and args[0] == 'get'), stdout_only=True).strip()

        def bound_config(profile):
            expected = expected_homes[profile] / 'config.yaml'
            plain_file(expected)
            actual = query(profile, 'path')
            require(Path(actual).absolute() == expected.absolute(), 'wrong profile path')
            return expected

        def profile_config(profile):
            cfg = bound_config(profile)
            if profile != 'default':
                soul = plain_file(expected_homes[profile] / 'SOUL.md')
                require(all(clause in soul for clause in ROLE_CONTRACTS[profile]), 'missing role protocol contract')
            model = json.loads(query(profile, 'get', 'model', '--json', '--raw'))
            require(isinstance(model, dict) and isinstance(model.get('default'), str) and bool(model['default'].strip()), 'missing model')
            # Mirror the pinned launcher's small awk reader exactly: its model is
            # a literal two-space default scalar, NOT necessarily the CLI value.
            in_model, launcher_model = False, None
            for line in plain_file(cfg).splitlines():
                if line.startswith('model:'):
                    in_model = True
                    continue
                if line and not line.startswith(' '):
                    in_model = False
                if in_model and line.startswith('  default:'):
                    launcher_model = re.sub(r'^  default: *', '', line)
                    break
            require(launcher_model == model['default'], 'CLI and launcher model disagree')
            # Provider may legitimately be omitted (Hermes auto-detects it).
            require('provider' not in model or isinstance(model['provider'], str) and bool(model['provider'].strip()), 'invalid provider')
            return 'exact launcher profile/config binding, model selection and role instructions present; credentials/provider reachability NOT TESTED'

        for profile in ['review', 'run', 'close', 'default']:
            audit('hermes profile ' + profile, lambda profile=profile: profile_config(profile))

        def hermes_hooks():
            cfg = bound_config('default')
            guard, auto = brain / '.claude/hooks/guard-git-refs.py', brain / 'auto-commit.sh'
            expected = {
                'pre_tool_call': ({'command': 'python3 ' + shlex.quote(str(guard)), 'matcher': 'terminal', 'timeout': 10}, guard),
                'on_session_end': ({'command': 'sh ' + shlex.quote(str(auto)) + ' --hermes-hook', 'timeout': 30}, auto),
            }
            lists = {}
            for event in expected:
                value = json.loads(query('default', 'get', 'hooks.' + event, '--json', '--raw'))
                lists[event] = [] if value is None else value
                require(isinstance(lists[event], list) and all(isinstance(e, dict) for e in lists[event]), 'invalid hook list')
            # No registration is a valid declined optional choice. A recognisable
            # brain command in either event makes the pair required, never optional.
            present = any(any(str(script) in str(e.get('command', '')) or brain.as_posix() in str(e.get('command', ''))
                              for e in lists[event]) for event, (_, script) in expected.items())
            if not present:
                record('hermes brain hooks', 'NOT CONFIGURED', 'optional default-profile hooks absent; role profiles do not require these brain-only hooks')
                return None
            approvals = object_file(cfg.parent / 'shell-hooks-allowlist.json').get('approvals')
            require(isinstance(approvals, list), 'invalid approvals')
            for event, (entry, script) in expected.items():
                plain_file(script)
                matches = [e for e in lists[event] if e.get('command') == entry['command']]
                require(len(matches) == 1 and all(matches[0].get(k) == v for k, v in entry.items()), 'wrong registration')
                require(matches[0].get('matcher') == entry.get('matcher'), 'wrong matcher')
                approved = [a for a in approvals if isinstance(a, dict) and a.get('event') == event and a.get('command') == entry['command']]
                require(len(approved) == 1, 'missing approval')
                stamp = datetime.datetime.fromisoformat(approved[0]['script_mtime_at_approval'].replace('Z', '+00:00'))
                require(stamp.tzinfo is not None and abs(stamp.timestamp() - script.stat().st_mtime) < 0.000001, 'stale approval')
                require(datetime.datetime.fromisoformat(approved[0]['approved_at'].replace('Z', '+00:00')).tzinfo is not None, 'invalid approval date')
            return 'default-profile event/command/matcher registrations, scripts and fresh mtime approvals verified; hook execution NOT TESTED'

        audit('hermes brain hooks', hermes_hooks)
    else:
        record('devin configuration', 'NOT TESTED', 'Devin has no kit role profiles; executable discovery only, auth and runtime not queried')
    record('backend authentication/runtime', 'NOT TESTED', 'no auth, model, login, hook execution or configuration mutation performed')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--brain', type=Path, default=SOURCE, help='installed brain root (read-only)')
    parser.add_argument('--live', action='store_true', help='spend model quota on isolated review/run/close/debrief')
    parser.add_argument('--backend', choices=['claude', 'hermes', 'devin'])
    parser.add_argument('--model', help='explicit live model override; unsupported models fail, never fall back')
    parser.add_argument('--timeout', type=int, default=1800, help='live process-group deadline in seconds')
    parser.add_argument('--keep', action='store_true', help='keep private fixture/logs (may contain model output)')
    parser.add_argument('--json', action='store_true', help='machine-readable scoped results')
    args = parser.parse_args(argv)
    if args.timeout <= 0 or (args.model and not args.live):
        parser.error('--timeout must be positive; --model requires --live')
    results = []

    def record(name, status, detail):
        results.append({'check': name, 'status': status, 'detail': detail})

    def check(name, fn):
        try:
            detail = fn()
            record(name, 'PASS', detail)
        except (CheckError, OSError, ValueError, SyntaxError):
            # Do not disclose secrets or private contents via exception text.
            record(name, 'FAIL', 'verification failed; check installation/configuration and private fixture artifacts')

    brain = args.brain.absolute()
    config = {}

    def configuration():
        nonlocal config
        config = read_env(brain / 'brain.env')
        require(config.get('DEFAULT_BACKEND') in ['claude', 'hermes', 'devin'], 'missing backend')
        require((brain / 'AGENTS.local.md').is_file(), 'missing local constitution')
        require((brain / '02-projects/_templates/handoff-defaults.yml').is_file(), 'missing handoff defaults')
        installed = read_env(Path.home() / '.config/handoff/config.env', last=True)
        roots = {key: os.environ.get(key) or installed.get(key, '').strip('\"\'')
                 for key in ['VAULT', 'HANDOFF_DEFAULTS', 'HANDOFF_PROJECTS']}
        require(roots['VAULT'] and Path(roots['VAULT']).resolve() == brain.resolve(), 'installed launcher targets another brain')
        require(roots['HANDOFF_DEFAULTS'] == '02-projects/_templates/handoff-defaults.yml' and roots['HANDOFF_PROJECTS'] == '02-projects', 'unexpected launcher roots')
        return 'brain and installed launcher roots agree; no login/model request made'

    check('configuration', configuration)
    for command in ['git', 'handoff-launch', 'handoff-orchestrate', 'brief-check']:
        check(command, lambda command=command: str(shutil.which(command) or require(False, 'missing command')))
    backend = args.backend or config.get('DEFAULT_BACKEND', 'claude')
    check('backend executable', lambda: str(shutil.which(backend) or require(False, 'missing backend')))
    backend_diagnostics(brain, backend, record)
    env = git_environment(dict(os.environ))
    fixture = None
    # Unique directory under the OS's configured TMPDIR; no CODE_ROOT/user demo read or write.
    with tempfile.TemporaryDirectory(prefix='agent-brain-check-') as tmp:
        root = Path(tmp)
        os.chmod(root, 0o700)
        launcher_env = None

        def local_fixture():
            nonlocal fixture
            fixture = make_fixture(root / 'canary', SOURCE, env)
            require(run([sys.executable, '-m', 'unittest', '-q'], fixture['repo'], env) is not None, 'baseline test failure')
            require(run([sys.executable, 'hello.py'], fixture['repo'], env) == 'Hello, world!\n', 'baseline failure')
            return 'isolated Git fixture and baseline tests passed (no agent started)'

        check('local canary baseline', local_fixture)
        def protocol_preflight():
            nonlocal launcher_env
            require(fixture is not None, 'no baseline fixture')
            require(backend in ['claude', 'hermes', 'devin'], 'unsupported configured backend')
            launcher_env = isolate_launcher_home(fixture, backend, env)
            launcher_env.update(VAULT=str(fixture['notes']), HANDOFF_DEFAULTS='02-projects/_templates/handoff-defaults.yml', HANDOFF_PROJECTS='02-projects')
            output = run(['brief-check', str(fixture['brief'])], fixture['notes'], launcher_env)
            require(re.search(r'^RESULT 0 FAIL\b', output, re.M), 'brief-check did not report zero failures')
            output = run(['handoff-launch', 'loop', str(fixture['brief']), '--gate', 'auto', '--backend', backend, '--dry-run'], fixture['notes'], launcher_env)
            require('DRY RUN loop' in output, 'launcher did not confirm dry-run')
            return 'brief-check and launcher dry-run passed; backend calls blocked (Devin auth prerequisite stubbed, authentication NOT TESTED)'

        check('handoff protocol preflight', protocol_preflight)
        # Optional integrations are never sent to, started or enabled here.
        for name, path, keys, enabled in [
            ('telegram', Path.home() / '.config/handoff/notify.env', ['TELEGRAM_BOT_TOKEN', 'TELEGRAM_CHAT_ID'], config.get('NOTIFY') == 'telegram'),
            ('journal', Path.home() / '.config/agent-brain/journal.env', ['PATH'], False),
        ]:
            try:
                values = read_env(path, last=True)
                configured = path.exists() or path.is_symlink() or enabled
                if not configured:
                    record(name, 'NOT CONFIGURED', 'optional; no configuration found')
                else:
                    require(all(values.get(k) for k in keys), 'incomplete integration config')
                    record(name + ' configuration', 'PASS', 'configuration present only; credentials not validated')
                    record(name, 'NOT TESTED', 'no send, job execution or timer activation performed')
            except (CheckError, OSError, ValueError):
                record(name, 'FAIL', 'invalid or incomplete optional configuration (values hidden)')
        if args.live:
            def live():
                require(fixture is not None, 'no baseline fixture')
                require(not any(r['status'] == 'FAIL' for r in results), 'local prerequisites failed')
                launcher = shutil.which('handoff-launch')
                require(launcher_env is not None, 'preflight did not initialize launcher')
                write_backend_shim(fixture, backend, live=True)
                sha = launch_live(fixture, launcher, backend, args.model, args.timeout, launcher_env)
                return 'review/revise/run/close/debrief artifacts, closed state, diff, commit ' + sha + ' and fresh tests verified'
            check('live handoff', live)
        else:
            record('live handoff', 'NOT TESTED', 'no paid requests; use --live to test model/auth and end-to-end stages')
        if args.keep:
            kept = Path(tempfile.mkdtemp(prefix='agent-brain-evidence-'))
            shutil.copytree(root, kept / 'evidence', symlinks=True)
            record('private evidence', 'PASS', str(kept / 'evidence'))
    if args.json:
        print(json.dumps({'results': results, 'live_requested': args.live}, indent=2))
    else:
        for r in results:
            print('%s: %s — %s' % (r['status'], r['check'], r['detail']))
        print('Local diagnostics only; NOT TESTED is never end-to-end PASS.' if not args.live else 'Live canary result is independent of optional integration status.')
    return 1 if any(r['status'] == 'FAIL' for r in results) else 0


if __name__ == '__main__':
    sys.exit(main())
