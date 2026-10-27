"""Offline acceptance-checker tests: no installed agent or provider is executed."""
import importlib.util

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('checker', ROOT / 'setup-check.py')
assert spec is not None and spec.loader is not None
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class AcceptanceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='acceptance-test-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.env = checker.git_environment(dict(os.environ))
        self.fixture = checker.make_fixture(self.root / 'fixture', ROOT, self.env)

    def complete(self):
        f = self.fixture
        repo = f['repo']
        (repo / 'hello.py').write_text('import sys\n\ndef greet(name="world"):\n    return f"Hello, {name}!"\n\nif __name__ == "__main__":\n    print("hello 0.1.0" if sys.argv[1:] == ["--version"] else greet(sys.argv[1] if sys.argv[1:] else "world"))\n')
        with (repo / 'test_hello.py').open('a') as out:
            out.write('\nclass VersionTest(unittest.TestCase):\n    def test_version(self):\n        import subprocess, sys\n        self.assertEqual(subprocess.check_output([sys.executable, "hello.py", "--version"], text=True), "hello 0.1.0\\n")\n')
        checker.run(['git', 'add', 'hello.py', 'test_hello.py'], repo, self.env)
        checker.run(['git', 'commit', '-qm', 'Add version output'], repo, self.env)
        b = f['brief']
        b.write_text(b.read_text().replace('handoff: draft', 'handoff: closed'))
        b.with_suffix('.review.md').write_text('=== HANDOFF REVIEW ===\nbrief-revision: 2026-10-10-r1\nverdict: RUN\n=== END HANDOFF REVIEW ===\n## Revise outcome\ngate: clean\n')
        b.with_suffix('.report.md').write_text('=== COMPLETION REPORT ===\nbrief-revision: 2026-10-10-r1\noutcome: COMPLETE\naudit: 0 refuted, 0 unconfirmed\n--- NOT DONE ---\n- none\n=== END COMPLETION REPORT ===\n## Debrief outcome\nClosed.\n')
        b.with_suffix('.close.md').write_text('=== CLOSE AUDIT ===\nVERDICT: PASS\nREPORT_REVISION: 2026-10-10-r1\n=== END CLOSE AUDIT ===\n')
        b.with_suffix('.done-when.md').write_text('# done-when · canary\n§4.1 · line 50 · exit 0 · 1s · sha256 abc\n  $ python3 -m unittest -q\n§4.2 · line 51 · exit 0 · 1s · sha256 def\n  $ python3 hello.py --version\n')

    def test_complete_requires_git_and_protocol_and_real_tests(self):
        self.complete()
        checker.verify_live(self.fixture, self.env)

    def revised(self):
        self.complete()
        b = self.fixture['brief']
        final = '2026-10-27-r2'
        b.write_text(b.read_text().replace('revision: ' + checker.REVISION, 'revision: ' + final))
        p = b.with_suffix('.review.md')
        p.write_text(p.read_text().replace('## Revise outcome', '## Revise outcome — ' + checker.REVISION + ' → ' + final))
        for suffix in ['.report.md', '.close.md']:
            p = b.with_suffix(suffix)
            p.write_text(p.read_text().replace(checker.REVISION, final))

    def test_authorized_revision_transition_is_accepted(self):
        self.revised()
        checker.verify_live(self.fixture, self.env)

    def test_revised_artifacts_must_bind_to_final_revision(self):
        self.revised()
        b = self.fixture['brief']
        for suffix in ['.report.md', '.close.md']:
            p = b.with_suffix(suffix)
            original = p.read_text()
            p.write_text(original.replace('2026-10-27-r2', checker.REVISION))
            with self.subTest(suffix=suffix), self.assertRaises(checker.CheckError):
                checker.verify_live(self.fixture, self.env)
            p.write_text(original)

    def test_revision_change_requires_recorded_transition(self):
        self.revised()
        p = self.fixture['brief'].with_suffix('.review.md')
        p.write_text(p.read_text().replace(' → 2026-10-27-r2', ' → wrong-revision'))
        with self.assertRaises(checker.CheckError):
            checker.verify_live(self.fixture, self.env)

    def test_report_alone_is_not_pass(self):
        self.complete()
        checker.run(['git', 'reset', '--hard', self.fixture['base']], self.fixture['repo'], self.env)
        with self.assertRaises(checker.CheckError):
            checker.verify_live(self.fixture, self.env)

    def test_missing_or_malformed_artifacts(self):
        self.complete()
        for suffix in ['.review.md', '.report.md', '.close.md', '.done-when.md']:
            p = self.fixture['brief'].with_suffix(suffix)
            original = p.read_text()
            p.unlink()
            with self.subTest(missing=suffix), self.assertRaises(checker.CheckError):
                checker.verify_live(self.fixture, self.env)
            p.write_text('PASS\n')
            with self.subTest(malformed=suffix), self.assertRaises(checker.CheckError):
                checker.verify_live(self.fixture, self.env)
            p.write_text(original)

    def test_protocol_failures(self):
        self.complete()
        mutations = [('.review.md', 'gate: clean', 'gate: held'),
                     ('.review.md', 'verdict: RUN', 'verdict: REWRITE'),
                     ('.report.md', 'outcome: COMPLETE', 'outcome: BLOCKED'),
                     ('.report.md', '- none', '- missing test'),
                     ('.close.md', 'VERDICT: PASS', 'VERDICT: FAIL'),
                     ('.md', 'handoff: closed', 'handoff: reported')]
        for suffix, before, after in mutations:
            p = self.fixture['brief'] if suffix == '.md' else self.fixture['brief'].with_suffix(suffix)
            original = p.read_text()
            p.write_text(original.replace(before, after))
            with self.subTest(after=after), self.assertRaises(checker.CheckError):
                checker.verify_live(self.fixture, self.env)
            p.write_text(original)

    def test_artifact_symlink_refused(self):
        self.complete()
        p = self.fixture['brief'].with_suffix('.close.md')
        target = self.root / 'user-content'
        target.write_text(p.read_text())
        p.unlink()
        p.symlink_to(target)
        with self.assertRaises(checker.CheckError):
            checker.verify_live(self.fixture, self.env)

    def test_dirty_tree_and_unexpected_diff_refused(self):
        self.complete()
        (self.fixture['repo'] / 'extra').write_text('unexpected')
        with self.assertRaises(checker.CheckError):
            checker.verify_live(self.fixture, self.env)
        checker.run(['git', 'add', 'extra'], self.fixture['repo'], self.env)
        checker.run(['git', 'commit', '-qm', 'Unexpected edit'], self.fixture['repo'], self.env)
        with self.assertRaises(checker.CheckError):
            checker.verify_live(self.fixture, self.env)

    def test_existing_fixture_and_symlink_are_not_reused(self):
        for p in [self.fixture['root'], self.root / 'link']:
            if not p.exists():
                p.symlink_to(self.fixture['root'], target_is_directory=True)
            with self.assertRaises((checker.CheckError, FileExistsError)):
                checker.make_fixture(p, ROOT, self.env)

    def test_repeated_fixtures_are_independent(self):
        other = checker.make_fixture(self.root / 'other', ROOT, self.env)
        self.assertNotEqual(other['repo'], self.fixture['repo'])
        self.assertEqual(checker.run(['git', 'remote', 'get-url', 'origin'], other['repo'], self.env).strip(), str(other['root'] / 'origin.git'))

    def test_offline_cli_never_executes_backend(self):
        home = self.root / 'home'
        home.mkdir()
        bins = self.root / 'bin'
        bins.mkdir()
        marker = self.root / 'called'
        for name in ['claude', 'hermes']:
            p = bins / name
            p.write_text('#!/bin/sh\ntouch "' + str(marker) + '"\nexit 91\n')
            p.chmod(0o755)
        for name, response in [('handoff-launch', 'DRY RUN loop'), ('brief-check', 'RESULT 0 FAIL'), ('handoff-orchestrate', '')]:
            p = bins / name
            p.write_text('#!/bin/sh\necho "' + response + '"\n')
            p.chmod(0o755)
        (home / 'brain.env').write_text('DEFAULT_BACKEND=claude\n')
        env = dict(os.environ, HOME=str(home), PATH=str(bins) + os.pathsep + os.environ['PATH'])
        result = subprocess.run([sys.executable, str(ROOT / 'setup-check.py'), '--brain', str(home)], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)  # incomplete brain, not a false PASS
        self.assertIn('NOT TESTED', result.stdout)
        self.assertIn('NOT CONFIGURED', result.stdout)
        self.assertFalse(marker.exists())

    def test_nonzero_launcher_never_passes(self):
        fake = self.root / 'fail-launch'
        fake.write_text('#!/bin/sh\necho "unsupported model or authentication failure"\nexit 9\n')
        fake.chmod(0o755)
        with self.assertRaises(checker.CheckError):
            checker.launch_live(self.fixture, str(fake), 'claude', None, 10, self.env)

    def test_executable_fake_success_is_independently_verified(self):
        # An actual child process writes artifacts and makes real local commits.
        # This is explicitly an offline fake, not proof of a live provider run.
        f = self.fixture
        metadata = self.root / 'fixture.json'
        metadata.write_text(json.dumps({k: str(v) if isinstance(v, Path) else v for k, v in f.items()}))

        fake = self.root / 'fake-launch'
        fake.write_text('#!' + sys.executable + '\nimport os, json, sys\nfrom pathlib import Path\nsys.path.insert(0, ' + repr(str(ROOT / 'tests')) + ')\nimport setup_acceptance_test as tests\nx = tests.AcceptanceTests()\nx.env = tests.checker.git_environment(dict(os.environ))\nx.fixture = json.loads(Path(' + repr(str(metadata)) + ').read_text())\nfor key in ["root", "repo", "notes", "brief"]: x.fixture[key] = Path(x.fixture[key])\nx.complete()\n')
        fake.chmod(0o755)
        sha = checker.launch_live(f, str(fake), 'claude', 'unsupported-fake-model', 10, self.env)
        self.assertEqual(len(sha), 40)

    def test_zero_exit_without_artifacts_is_not_pass(self):
        fake = self.root / 'empty-launch'
        fake.write_text('#!/bin/sh\necho PASS\nexit 0\n')
        fake.chmod(0o755)
        with self.assertRaises(checker.CheckError):
            checker.launch_live(self.fixture, str(fake), 'claude', None, 10, self.env)

    def test_failed_committed_test_is_not_pass(self):
        self.complete()
        repo = self.fixture['repo']
        with (repo / 'test_hello.py').open('a') as out:
            out.write('\nclass FailureTest(unittest.TestCase):\n    def test_failure(self):\n        self.fail("adversarial")\n')
        checker.run(['git', 'add', 'test_hello.py'], repo, self.env)
        checker.run(['git', 'commit', '-qm', 'Failing test'], repo, self.env)
        with self.assertRaises(checker.CheckError):
            checker.verify_live(self.fixture, self.env)

    def test_missing_new_test_is_not_pass(self):
        self.complete()
        repo = self.fixture['repo']
        (repo / 'test_hello.py').write_text(self.fixture['original_tests'] + '\n# not coverage\n')
        checker.run(['git', 'add', 'test_hello.py'], repo, self.env)
        checker.run(['git', 'commit', '-qm', 'Remove coverage'], repo, self.env)
        with self.assertRaises(checker.CheckError):
            checker.verify_live(self.fixture, self.env)

    def test_timeout_kills_launcher_and_preserves_private_log(self):
        fake = self.root / 'slow-launch'
        fake.write_text('#!/bin/sh\necho private-output\nsleep 60\n')
        fake.chmod(0o755)
        with self.assertRaises(checker.CheckError):
            checker.launch_live(self.fixture, str(fake), 'claude', None, 0.1, self.env)
        self.assertIn('private-output', (self.fixture['root'] / 'launcher.log').read_text())

    def test_optional_statuses_are_scoped_and_secret_free(self):
        home = self.root / 'optional-home'
        (home / '.config/handoff').mkdir(parents=True)
        token = 'TEST-SECRET-DO-NOT-PRINT'
        (home / '.config/handoff/notify.env').write_text('TELEGRAM_BOT_TOKEN=' + token + '\nTELEGRAM_CHAT_ID=42\n')
        bins = self.root / 'optional-bin'
        bins.mkdir()
        for name, output in [('brief-check', 'RESULT 0 FAIL'), ('handoff-launch', 'DRY RUN loop'), ('handoff-orchestrate', ''), ('claude', '')]:
            p = bins / name
            p.write_text('#!/bin/sh\necho "' + output + '"\n')
            p.chmod(0o755)
        env = dict(os.environ, HOME=str(home), PATH=str(bins) + os.pathsep + os.environ['PATH'])
        p = subprocess.run([sys.executable, str(ROOT / 'setup-check.py'), '--brain', str(home), '--json'], env=env, text=True, capture_output=True)
        data = json.loads(p.stdout)
        statuses = {r['check']: r['status'] for r in data['results']}
        self.assertEqual(statuses['telegram configuration'], 'PASS')
        self.assertEqual(statuses['telegram'], 'NOT TESTED')
        self.assertEqual(statuses['journal'], 'NOT CONFIGURED')
        self.assertNotIn(token, p.stdout + p.stderr)
        (home / '.config/handoff/notify.env').write_text('TELEGRAM_CHAT_ID=42\n')
        p = subprocess.run([sys.executable, str(ROOT / 'setup-check.py'), '--brain', str(home), '--json'], env=env, text=True, capture_output=True)
        self.assertEqual(p.returncode, 1)
        statuses = {r['check']: r['status'] for r in json.loads(p.stdout)['results']}
        self.assertEqual(statuses['telegram'], 'FAIL')

    def test_token_new_test_is_not_regression_coverage(self):
        self.complete()
        repo = self.fixture['repo']
        (repo / 'test_hello.py').write_text(self.fixture['original_tests'] + '\nclass TokenTest(unittest.TestCase):\n    def test_token(self):\n        self.assertTrue(True)\n')
        checker.run(['git', 'add', 'test_hello.py'], repo, self.env)
        checker.run(['git', 'commit', '-qm', 'Token test'], repo, self.env)
        with self.assertRaises(checker.CheckError):
            checker.verify_live(self.fixture, self.env)

    def test_log_collision_does_not_execute_or_overwrite(self):
        target = self.root / 'user-log'
        target.write_text('preserve me')
        (self.fixture['root'] / 'launcher.log').symlink_to(target)
        with self.assertRaises(FileExistsError):
            checker.launch_live(self.fixture, '/not/executed', 'claude', None, 1, self.env)
        self.assertEqual(target.read_text(), 'preserve me')

    @unittest.skipUnless(os.environ.get('SMOKE_KIT'), 'set SMOKE_KIT for real pinned-launcher preflight')
    def test_pinned_devin_dry_run_never_calls_real_backend(self):
        kit = Path(os.environ['SMOKE_KIT'])
        bins = self.root / 'devin-bin'
        bins.mkdir()
        marker = self.root / 'devin-called'
        p = bins / 'devin'
        p.write_text('#!/bin/sh\necho "$*" >> ' + str(marker) + '\necho "logged in"\n')
        p.chmod(0o755)
        for name, target in [('handoff-launch', 'handoff-launch.sh'), ('brief-check', 'brief-check.sh'), ('handoff-orchestrate', 'handoff-orchestrate.sh')]:
            (bins / name).symlink_to(kit / target)
        home = self.root / 'devin-home'
        config = home / '.config/handoff'
        config.mkdir(parents=True)
        config.joinpath('config.env').write_text('VAULT=' + str(self.fixture['notes']) + '\nHANDOFF_DEFAULTS=02-projects/_templates/handoff-defaults.yml\nHANDOFF_PROJECTS=02-projects\n')
        env = dict(self.env, HOME=str(home), PATH=str(bins) + os.pathsep + self.env['PATH'])
        result = subprocess.run([sys.executable, str(ROOT / 'setup-check.py'), '--brain', str(self.fixture['notes']), '--backend', 'devin'], env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(marker.exists(), 'real Devin auth command was executed during free preflight')
        result = subprocess.run([sys.executable, str(ROOT / 'setup-check.py'), '--brain', str(self.fixture['notes']), '--backend', 'devin', '--live', '--model', 'unsupported-canary-model'], env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('FAIL: live handoff', result.stdout)
        self.assertTrue(marker.exists(), 'explicit live path never reached installed backend fake')


if __name__ == '__main__':
    unittest.main()
