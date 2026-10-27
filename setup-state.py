#!/usr/bin/env python3
"""Read-only component checks for setup; preferences never prove installation."""
import hashlib
import os
from pathlib import Path
import sys


def same_tree(source, target):
    if not source.is_dir() or not target.is_dir():
        return False
    left = {p.relative_to(source): p.read_bytes() for p in source.rglob('*') if p.is_file()}
    right = {p.relative_to(target): p.read_bytes() for p in target.rglob('*') if p.is_file()}
    return left == right


def kit_ready(kit, brain, home):
    for name in ('handoff-launch', 'handoff-orchestrate', 'brief-check'):
        link = home / '.local/bin' / name
        if not link.is_symlink() or link.resolve() != kit / (name + '.sh') or not os.access(link, os.X_OK):
            return False
    try:
        config = (home / '.config/handoff/config.env').read_text().splitlines()
    except OSError:
        return False
    for key, value in {'VAULT': str(brain), 'HANDOFF_DEFAULTS': '02-projects/_templates/handoff-defaults.yml',
                       'HANDOFF_PROJECTS': '02-projects'}.items():
        lines = [line for line in config if line.startswith(key + '=')]
        if lines != [key + '=' + value]:
            return False
    for src in (kit / 'skills').iterdir():
        if src.is_dir() and not same_tree(src, home / '.claude/skills' / src.name):
            return False
    for name in ('handoff-watchdog@.service', 'handoff-watchdog@.timer'):
        src, dst = kit / 'systemd' / name, home / '.config/systemd/user' / name
        if not dst.is_file() or src.read_bytes() != dst.read_bytes():
            return False
    return True


def journal_ready(brain, home, daily, weekly):
    # Installer output must agree with current source as well as the desired times.
    import subprocess
    if (home / '.config/agent-brain/journal.env').read_text() != 'PATH=' + os.environ['PATH'] + '\n':
        return False
    if sys.platform == 'darwin':
        import plistlib
        suffix = hashlib.sha256(str(brain).encode()).hexdigest()[:8]
        for job, time in [('daily', daily), ('weekly', weekly)]:
            path = home / 'Library/LaunchAgents' / ('io.github.tissarni.agent-brain.journal.' + job + '.' + suffix + '.plist')
            if not path.is_file():
                return False
            data = plistlib.loads(path.read_bytes())
            from xml.sax.saxutils import escape
            h, m = map(int, time.split(':'))
            days = [1, 2, 3, 4, 5] if job == 'daily' else [1]
            calendar = '\n'.join(
                f'    <dict><key>Weekday</key><integer>{d}</integer><key>Hour</key><integer>{h}</integer>'
                f'<key>Minute</key><integer>{m}</integer></dict>' for d in days)
            expected = (brain / 'journal/launchd/journal.plist.in').read_text()
            logdir = Path(os.environ.get('XDG_STATE_HOME', str(home / '.local/state'))) / 'agent-brain'
            for k, v in [('@LABEL@', data['Label']), ('@BRAIN@', escape(str(brain))), ('@JOB@', job),
                         ('@PATH@', escape(os.environ['PATH'])), ('@LOG@', escape(str(logdir / ('journal-' + job + '.log')))),
                         ('@CALENDAR@', calendar)]:
                expected = expected.replace(k, v)
            if path.read_text() != expected:
                return False
            calendars = data.get('StartCalendarInterval', [])
            if isinstance(calendars, dict):
                calendars = [calendars]
            h, m = map(int, time.split(':'))
            if not calendars or any(c.get('Hour') != h or c.get('Minute') != m for c in calendars):
                return False
            result = subprocess.run(['launchctl', 'print', 'gui/%s/%s' % (os.getuid(), data['Label'])], capture_output=True)
            if result.returncode:
                return False
    else:
        result = subprocess.run(['systemd-escape', '--path', str(brain)], capture_output=True, text=True)
        if result.returncode:
            return False
        instance = result.stdout.strip()
        units = home / '.config/systemd/user'
        for job, time in [('daily', daily), ('weekly', weekly)]:
            for kind in ('service', 'timer'):
                name = 'agent-brain-journal-%s@.%s' % (job, kind)
                src, dst = brain / 'journal/systemd' / name, units / name
                if not dst.is_file() or src.read_bytes() != dst.read_bytes():
                    return False
            name = 'agent-brain-journal-%s@%s.timer' % (job, instance)
            conf = units / (name + '.d') / 'time.conf'
            days = 'Mon..Fri' if job == 'daily' else 'Mon'
            expected = '[Timer]\nOnCalendar=\nOnCalendar=%s *-*-* %s:00\n' % (days, time)
            if not conf.is_file() or conf.read_text() != expected:
                return False
            for action in ('is-enabled', 'is-active'):
                if subprocess.run(['systemctl', '--user', action, name], capture_output=True).returncode:
                    return False
    return True


def journal_times(brain, home):
    import re
    import subprocess
    times = []
    for job in ('daily', 'weekly'):
        if sys.platform == 'darwin':
            import plistlib
            suffix = hashlib.sha256(str(brain).encode()).hexdigest()[:8]
            path = home / 'Library/LaunchAgents' / ('io.github.tissarni.agent-brain.journal.' + job + '.' + suffix + '.plist')
            data = plistlib.loads(path.read_bytes())
            entries = data['StartCalendarInterval']
            if isinstance(entries, dict):
                entries = [entries]
            h, m = entries[0]['Hour'], entries[0]['Minute']
            value = '%02d:%02d' % (h, m)
        else:
            instance = subprocess.check_output(['systemd-escape', '--path', str(brain)], text=True).strip()
            path = home / '.config/systemd/user' / ('agent-brain-journal-%s@%s.timer.d' % (job, instance)) / 'time.conf'
            match = re.search(r'^OnCalendar=.+ ([0-9]{2}:[0-9]{2}):00$', path.read_text(), re.M)
            if not match:
                return 1
            value = match[1]
        if not re.fullmatch(r'(?:[01][0-9]|2[0-3]):[0-5][0-9]', value):
            return 1
        times.append(value)
    print(' '.join(times))
    return 0


def update_identity(brain, arguments):
    import re
    path = brain / 'AGENTS.local.md'
    text = path.read_text()
    before, heading, rest = text.partition('## Who I am\n')
    section, boundary, after = rest.partition('\n## ')
    if not heading:
        return 1
    pairs = list(zip(arguments[::2], arguments[1::2]))
    patterns = [r'(?m)^([^\n]+?) — ([^\n]*?)\.$', r'(?m)^([^\n]+?) — ([^\n]*?)\.$',
                r'(?m)^Working languages: ([^\n]*?)\.$', r'(?m)^Principles: ([^\n]*?)\.$']
    # Only the seed's complete, unambiguous three-line prefix is machine-owned.
    # Validate before changing anything, even if just one override was requested.
    canonical = r'[^\n]+? — [^\n]*?\.\nWorking languages: [^\n]*?\.\nPrinciples: [^\n]*?\.(?:\n|$)'
    if not re.match(canonical, section) or any(len(re.findall(p, section)) != 1 for p in patterns):
        return 1
    for index, (flag, value) in enumerate(pairs):
        if flag != '1':
            continue
        match = re.search(patterns[index], section)
        if not match:
            return 1  # A custom identity layout is never guessed at or destroyed.
        if index < 2:
            name, role = match.groups()
            replacement = (value if index == 0 else name) + ' — ' + (value if index == 1 else role) + '.'
        else:
            replacement = ('Working languages: ' if index == 2 else 'Principles: ') + value + '.'
        section = section[:match.start()] + replacement + section[match.end():]
    path.write_text(before + heading + section + boundary + after)
    return 0


def main():
    mode, kit_arg, brain_arg = sys.argv[1:4]
    kit, brain, home = Path(kit_arg).resolve(), Path(brain_arg).resolve(), Path.home()
    if mode == 'identity':
        return update_identity(brain, sys.argv[4:])
    if mode == 'kit':
        return 0 if kit_ready(kit, brain, home) else 1
    if mode == 'journal':
        return 0 if journal_ready(brain, home, *sys.argv[4:6]) else 1
    if mode == 'journal-times':
        return journal_times(brain, home)
    raise ValueError('unknown component')


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError):
        sys.exit(1)
