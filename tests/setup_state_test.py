"""Identity reconciliation never guesses at a customized field layout."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('state', Path(__file__).resolve().parents[1] / 'setup-state.py')
assert spec is not None and spec.loader is not None
state = importlib.util.module_from_spec(spec)
spec.loader.exec_module(state)


class IdentityTests(unittest.TestCase):
    canonical = 'Original — Engineer.\nWorking languages: Python.\nPrinciples: KISS.\n'

    def update(self, section):
        with tempfile.TemporaryDirectory() as tmp:
            brain = Path(tmp)
            path = brain / 'AGENTS.local.md'
            original = '# Local\n\n## Who I am\n' + section + '\n## Local rules\nKeep this.\n'
            path.write_text(original)
            result = state.update_identity(brain, ['1', 'New', '1', 'Operator', '0', '', '0', ''])
            return result, original, path.read_text()

    def test_standard_fields_preserve_personal_notes(self):
        result, original, changed = self.update(self.canonical + '\nPersonal note.\n')
        self.assertEqual(result, 0)
        self.assertEqual(changed, original.replace('Original — Engineer.', 'New — Operator.'))

    def test_preceding_custom_identity_line_refuses_without_write(self):
        result, original, changed = self.update('Team — Platform.\n' + self.canonical)
        self.assertEqual(result, 1)
        self.assertEqual(changed, original)

    def test_duplicate_identity_refuses_without_write(self):
        result, original, changed = self.update(self.canonical + 'Other — Identity.\n')
        self.assertEqual(result, 1)
        self.assertEqual(changed, original)

    def test_incomplete_custom_layout_refuses_without_partial_write(self):
        result, original, changed = self.update('Original — Engineer.\nMy custom languages.\n')
        self.assertEqual(result, 1)
        self.assertEqual(changed, original)
