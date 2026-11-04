"""Exercise the CI composer against local repositories, without GitHub access."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).with_name('compose_avatar_sources.sh').resolve()
SAPI = 'neura/sapi-native-visemes'
MOTION = 'feature/fluent-motion-neura'


class AvatarSourceCompositionTests(unittest.TestCase):
    def git(self, root, *args):
        result = subprocess.run(
            ['git', '-C', str(root), *args], capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='avatar composition ')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.origin = self.root / 'origin'
        self.origin.mkdir()
        self.git(self.origin, 'init', '-b', 'subject')
        self.git(self.origin, 'config', 'user.name', 'Synthetic validation')
        self.git(self.origin, 'config', 'user.email', 'validation@local.invalid')
        self.git(self.origin, 'config', 'commit.gpgsign', 'false')
        self.git(self.origin, 'config', 'core.autocrlf', 'false')
        (self.origin / 'shared.txt').write_text('base\n')
        self.base = self.commit('base')
        self.git(self.origin, 'checkout', '-b', SAPI, self.base)
        (self.origin / 'speech.txt').write_text('speech\n')
        self.sapi = self.commit('speech')
        self.git(self.origin, 'checkout', '-b', MOTION, self.base)
        (self.origin / 'motion.txt').write_text('motion\n')
        self.motion = self.commit('motion')
        self.git(self.origin, 'checkout', 'subject')

    def commit(self, message):
        self.git(self.origin, 'add', '.')
        self.git(self.origin, 'commit', '-m', message)
        return self.git(self.origin, 'rev-parse', 'HEAD')

    def compose(self, *, shallow=True, branch='subject', **overrides):
        checkout = self.root / 'checkout'
        options = ['--depth=1'] if shallow else []
        self.git(self.root, 'clone', '--single-branch', '--branch', branch,
                 *options, self.origin.as_uri(), str(checkout))
        self.git(checkout, 'config', 'commit.gpgsign', 'false')
        summary = self.root / 'summary.txt'
        env = dict(os.environ, BASE_HEAD=self.base, SAPI_HEAD=self.sapi,
                   MOTION_HEAD=self.motion, HEAD_REF=branch,
                   MOTION_IN_BASE='false',
                   GITHUB_STEP_SUMMARY=str(summary))
        env.update(overrides)
        result = subprocess.run(
            [os.environ.get('COMPOSER_BASH', 'bash'), SCRIPT.as_posix()],
            cwd=checkout, env=env,
            capture_output=True, text=True,
        )
        report_path = checkout / 'avatar-integration-source.txt'
        self.assertTrue(report_path.is_file(), result.stdout + result.stderr)
        report = report_path.read_text()
        self.assertEqual(summary.read_text(), report)
        return result, report, checkout

    def assert_success(self, result, report, checkout):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('Status: complete\n', report)
        tree = self.git(checkout, 'rev-parse', 'HEAD^{tree}')
        self.assertIn(f'Combined tree: {tree}', report)
        for pin in (self.base, self.sapi, self.motion):
            self.git(checkout, 'merge-base', '--is-ancestor', pin, 'HEAD')
        self.assertTrue((checkout / 'speech.txt').exists())
        self.assertTrue((checkout / 'motion.txt').exists())

    def assert_failure(self, result, report, phase):
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Status: failed; no validated combined tree', report)
        self.assertIn(f'Last phase: {phase}', report)
        self.assertNotIn('Combined tree:', report)

    def test_success_from_shallow_checkout(self):
        self.assert_success(*self.compose())

    def test_success_from_full_checkout(self):
        self.assert_success(*self.compose(shallow=False))

    def test_stale_sapi_pin_retains_expected_and_observed_heads(self):
        result, report, _ = self.compose(SAPI_HEAD=self.base)
        self.assert_failure(result, report, 'verify SAPI head')
        self.assertIn(f'expected {self.base}; observed {self.sapi}', report)
        self.assertIn('Review and refresh the pin', result.stderr)

    def test_stale_motion_pin_retains_expected_and_observed_heads(self):
        result, report, _ = self.compose(MOTION_HEAD=self.base)
        self.assert_failure(result, report, 'verify motion head')
        self.assertIn(f'expected {self.base}; observed {self.motion}', report)

    def test_current_feature_branch_uses_checked_out_revision(self):
        self.assert_success(*self.compose(branch=SAPI, SAPI_HEAD=self.base))

    def test_missing_remote_branch_retains_diagnostics(self):
        self.git(self.origin, 'branch', '-D', SAPI)
        result, report, _ = self.compose()
        self.assert_failure(result, report, 'verify SAPI head')
        self.assertIn('unable to read remote head', report)

    def test_conflicting_merge_fails_and_records_unmerged_paths(self):
        self.git(self.origin, 'checkout', SAPI)
        (self.origin / 'shared.txt').write_text('speech change\n')
        self.sapi = self.commit('speech conflict')
        self.git(self.origin, 'checkout', MOTION)
        (self.origin / 'shared.txt').write_text('motion change\n')
        self.motion = self.commit('motion conflict')
        self.git(self.origin, 'checkout', 'subject')
        result, report, _ = self.compose()
        self.assert_failure(result, report, 'merge motion')
        self.assertIn('Unmerged paths:\nshared.txt\n', report)

    def test_unfetchable_base_fails_and_keeps_report(self):
        result, report, _ = self.compose(BASE_HEAD='0' * 40)
        self.assert_failure(result, report, 'fetch pinned history')

    def test_merged_motion_does_not_need_deleted_feature_branch(self):
        self.git(self.origin, 'merge', '--no-edit', MOTION)
        self.base = self.motion
        self.git(self.origin, 'branch', '-D', MOTION)
        result, report, checkout = self.compose(MOTION_IN_BASE='true')
        self.assert_success(result, report, checkout)
        self.assertIn('Verified merged motion commit is contained', report)

    def test_merged_motion_outside_base_fails_closed(self):
        result, report, _ = self.compose(MOTION_IN_BASE='true')
        self.assert_failure(result, report, 'verify merged motion ancestry')

    def test_only_conflicting_conversation_harness_keeps_source_version(self):
        workflow = self.origin / '.github/workflows/neura-avatar-conversation.yml'
        workflow.parent.mkdir(parents=True)
        workflow.write_text('reviewed current harness\n')
        self.commit('current workflow')
        self.git(self.origin, 'checkout', SAPI)
        workflow.parent.mkdir(parents=True, exist_ok=True)
        workflow.write_text('older dependency harness\n')
        self.sapi = self.commit('dependency workflow')
        self.git(self.origin, 'checkout', 'subject')
        result, report, checkout = self.compose()
        self.assert_success(result, report, checkout)
        self.assertEqual(
            (checkout / workflow.relative_to(self.origin)).read_text(),
            'reviewed current harness\n',
        )
        self.assertIn('Conversation workflow conflict policy keeps source PR head:', report)

    def test_conflicting_windows_speech_harness_keeps_source_version(self):
        workflow = self.origin / '.github/workflows/neura-windows-tts.yml'
        workflow.parent.mkdir(parents=True)
        workflow.write_text('reviewed startup voice harness\n')
        self.commit('current speech workflow')
        self.git(self.origin, 'checkout', SAPI)
        workflow.parent.mkdir(parents=True, exist_ok=True)
        workflow.write_text('dependency speech harness\n')
        self.sapi = self.commit('dependency speech workflow')
        self.git(self.origin, 'checkout', 'subject')
        result, report, checkout = self.compose()
        self.assert_success(result, report, checkout)
        self.assertEqual(
            (checkout / workflow.relative_to(self.origin)).read_text(),
            'reviewed startup voice harness\n',
        )
        self.assertIn('Windows speech workflow conflict policy keeps source PR head:', report)


if __name__ == '__main__':
    unittest.main()
