"""Read-only backend diagnostics using only disposable config fixtures."""
import datetime
import importlib.util
import json
import os
from pathlib import Path
import shlex
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('checker', Path(__file__).resolve().parents[1] / 'setup-check.py')
assert spec is not None and spec.loader is not None
c = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c)


class BackendDiagnostics(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.brain = self.root / 'brain'
        self.brain.mkdir()
        self.home = self.root / 'home'
        self.home.mkdir()
        self.results = []
        self.secret = 'CREDENTIAL-SENTINEL-DO-NOT-PRINT'
        self.bin = self.root / 'hermes'
        self.calls = self.root / 'calls'
        self.data = self.root / 'responses'
        self.responses = {}
        self.bin.write_text('#!' + sys.executable + '\nimport json,sys\nfrom pathlib import Path\na=sys.argv[1:]\nwith Path(' + repr(str(self.calls)) + ').open("a") as f: f.write(json.dumps(a)+"\\n")\nd=json.loads(Path(' + repr(str(self.data)) + ').read_text())\nk=" ".join(a)\nif k not in d: print(' + repr(self.secret) + ',file=sys.stderr);sys.exit(9)\nprint(d[k])\n')
        self.bin.chmod(0o755)
        for profile in ['default', 'review', 'run', 'close']:
            d = self.home / '.hermes' if profile == 'default' else self.home / '.hermes/profiles' / profile
            d.mkdir(parents=True, exist_ok=True)
            (d / 'config.yaml').write_text('model:\n  default: example\n')
            (d / 'SOUL.md').write_text('\n\n'.join(c.ROLE_CONTRACTS.get(profile, ['Notes instructions'])))
            self.responses[f'-p {profile} config path'] = str(d / 'config.yaml')
            self.responses[f'-p {profile} config get model --json --raw'] = json.dumps({'default': 'example', 'provider': 'auto'})
        for event in ['pre_tool_call', 'on_session_end']:
            self.responses[f'-p default config get hooks.{event} --json --raw'] = '[]'

    def record(self, name, status, detail):
        self.results.append({'check': name, 'status': status, 'detail': detail})

    def diagnose(self, backend='hermes'):
        self.data.write_text(json.dumps(self.responses))
        c.backend_diagnostics(self.brain, backend, self.record, home=self.home, hermes=str(self.bin))
        self.assertNotIn(self.secret, json.dumps(self.results))
        if self.calls.exists():
            for line in self.calls.read_text().splitlines():
                args = json.loads(line)
                self.assertEqual(args[:1], ['-p'])
                self.assertEqual(args[2], 'config')
                self.assertIn(args[3], ['path', 'get'])
        return {r['check']: r['status'] for r in self.results}

    def hooks(self):
        scripts = [self.brain / '.claude/hooks/guard-git-refs.py', self.brain / 'auto-commit.sh']
        approvals = []
        for event, script, command, matcher, timeout in [
            ('pre_tool_call', scripts[0], 'python3 ' + shlex.quote(str(scripts[0])), 'terminal', 10),
            ('on_session_end', scripts[1], 'sh ' + shlex.quote(str(scripts[1])) + ' --hermes-hook', None, 30),
        ]:
            script.parent.mkdir(parents=True, exist_ok=True)
            script.write_text('not executed')
            entry = {'command': command, 'timeout': timeout}
            if matcher:
                entry['matcher'] = matcher
            self.responses[f'-p default config get hooks.{event} --json --raw'] = json.dumps([entry])
            approvals.append({'event': event, 'command': command, 'approved_at': '2026-01-01T00:00:00Z', 'script_mtime_at_approval': datetime.datetime.fromtimestamp(script.stat().st_mtime, datetime.timezone.utc).isoformat().replace('+00:00', 'Z')})
        p = self.home / '.hermes/shell-hooks-allowlist.json'
        p.write_text(json.dumps({'approvals': approvals}))
        return p

    def test_valid_profiles_optional_hooks_declined(self):
        r = self.diagnose()
        self.assertTrue(all(r['hermes profile ' + p] == 'PASS' for p in ['default', 'review', 'run', 'close']))
        self.assertEqual(r['hermes brain hooks'], 'NOT CONFIGURED')
        self.assertEqual(r['backend authentication/runtime'], 'NOT TESTED')

    def test_stderr_banner_does_not_corrupt_machine_readable_config(self):
        text = self.bin.read_text()
        self.bin.write_text(text.replace('print(d[k])', 'print(' + repr(self.secret) + ', file=sys.stderr)\nprint(d[k])'))
        r = self.diagnose()
        self.assertTrue(all(r['hermes profile ' + p] == 'PASS' for p in ['default', 'review', 'run', 'close']))
        self.assertEqual(r['hermes brain hooks'], 'NOT CONFIGURED')

    def test_valid_stdout_with_nonzero_exit_is_not_accepted(self):
        self.bin.write_text(self.bin.read_text().replace('print(d[k])', 'print(d[k])\nsys.exit(7)'))
        r = self.diagnose()
        self.assertFalse(any(r['hermes profile ' + p] == 'PASS' for p in ['default', 'review', 'run', 'close']))

    def test_missing_role_instructions(self):
        (self.home / '.hermes/profiles/run/SOUL.md').unlink()
        self.assertEqual(self.diagnose()['hermes profile run'], 'FAIL')

    def test_mismatched_launcher_model_and_wrong_role_contract(self):
        (self.home / '.hermes/profiles/run/config.yaml').write_text('model:\n  default: wrong-model\n')
        self.assertEqual(self.diagnose()['hermes profile run'], 'FAIL')
        (self.home / '.hermes/profiles/review/SOUL.md').write_text('unrelated instructions; no review contract')
        self.results = []
        self.assertEqual(self.diagnose()['hermes profile review'], 'FAIL')

    def test_malformed_missing_and_mismatched_model(self):
        for value in ['{bad', 'null', '{}', '{"default": ""}', '{"default": ["bad"]}']:
            self.responses['-p review config get model --json --raw'] = value
            self.results = []
            self.assertEqual(self.diagnose()['hermes profile review'], 'FAIL')

    def test_wrong_profile_path(self):
        self.responses['-p run config path'] = str(self.home / '.hermes/config.yaml')
        self.assertEqual(self.diagnose()['hermes profile run'], 'FAIL')

    def test_config_errors_do_not_disclose_credentials(self):
        del self.responses['-p close config get model --json --raw']
        self.assertEqual(self.diagnose()['hermes profile close'], 'NOT TESTED')

    def test_registered_hooks_and_fresh_approvals(self):
        self.hooks()
        self.assertEqual(self.diagnose()['hermes brain hooks'], 'PASS')

    def test_stale_or_malformed_approval(self):
        p = self.hooks()
        p.write_text('{"approvals": []}')
        self.assertEqual(self.diagnose()['hermes brain hooks'], 'FAIL')
        p.write_text('{bad')
        self.results = []
        self.assertEqual(self.diagnose()['hermes brain hooks'], 'FAIL')

    def test_actual_stale_approval_and_missing_config(self):
        self.hooks()
        script = self.brain / 'auto-commit.sh'
        os.utime(script, (script.stat().st_atime, script.stat().st_mtime + 2))
        self.assertEqual(self.diagnose()['hermes brain hooks'], 'FAIL')
        (self.home / '.hermes/profiles/review/config.yaml').unlink()
        self.results = []
        self.assertEqual(self.diagnose()['hermes profile review'], 'FAIL')

    def test_config_missing_key_is_not_success(self):
        self.bin.write_text('#!/bin/sh\nif [ "$4" = path ]; then if [ "$2" = default ]; then echo "' + str(self.home / '.hermes/config.yaml') + '"; else echo "' + str(self.home / '.hermes/profiles') + '/$2/config.yaml"; fi; exit 0; fi\necho "Config key not set" >&2\nexit 1\n')
        r = self.diagnose()
        self.assertEqual(r['hermes profile run'], 'FAIL')
        self.assertEqual(r['hermes brain hooks'], 'NOT CONFIGURED')

    def test_partial_wrong_matcher_and_missing_script(self):
        self.hooks()
        key = '-p default config get hooks.pre_tool_call --json --raw'
        value = self.responses[key]
        for broken in ['[]', value.replace('terminal', 'read_file'), '{}', value.replace('guard-git-refs.py', 'stale.py')]:
            self.responses[key] = broken
            self.results = []
            self.assertEqual(self.diagnose()['hermes brain hooks'], 'FAIL')
        self.responses[key] = value
        (self.brain / 'auto-commit.sh').unlink()
        self.results = []
        self.assertEqual(self.diagnose()['hermes brain hooks'], 'FAIL')

    def claude(self):
        d = self.brain / '.claude'
        d.mkdir(exist_ok=True)
        (d / 'settings.json').write_text((c.SOURCE / '.claude/settings.json').read_text())
        for script in ['context-guard.sh', '.claude/hooks/guard-git-refs.py', 'auto-commit.sh']:
            p = self.brain / script
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text('not executed')
        return d

    def test_role_protocol_clauses_match_pinned_kit(self):
        kit = os.environ.get('SMOKE_KIT')
        if not kit:
            self.skipTest('set SMOKE_KIT to verify canonical role clauses')
        for profile, clauses in c.ROLE_CONTRACTS.items():
            canonical = (Path(kit) / 'hermes/profiles' / profile / 'SOUL.md').read_text()
            for clause in clauses:
                self.assertIn(clause, canonical)

    def test_claude_valid_registration(self):
        self.claude()
        self.assertEqual(self.diagnose('claude')['claude brain hooks'], 'PASS')
        self.assertFalse(self.calls.exists())

    def test_claude_local_disable_and_malformed(self):
        d = self.claude()
        for text in ['{"disableAllHooks":true}', '{bad', '{"hooks":{"PreToolUse":[]}}']:
            (d / 'settings.local.json').write_text(text)
            self.results = []
            self.assertEqual(self.diagnose('claude')['claude brain hooks'], 'FAIL')

    def test_claude_missing_wrong_matcher_and_script(self):
        d = self.claude()
        p = d / 'settings.json'
        original = p.read_text()
        for text in ['{}', '{bad', original.replace('"Bash"', '"Read"')]:
            p.write_text(text)
            self.results = []
            self.assertEqual(self.diagnose('claude')['claude brain hooks'], 'FAIL')
        p.write_text(original)
        (self.brain / 'context-guard.sh').unlink()
        self.results = []
        self.assertEqual(self.diagnose('claude')['claude brain hooks'], 'FAIL')

    def test_devin_does_not_invent_profiles(self):
        r = self.diagnose('devin')
        self.assertEqual(r['devin configuration'], 'NOT TESTED')
        self.assertFalse(self.calls.exists())
