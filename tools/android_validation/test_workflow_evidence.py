import json
import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / '.github/workflows/neura-android-dependency-validation.yml'


class WorkflowEvidenceTests(unittest.TestCase):
    def test_early_failures_and_cancellation_leave_uploadable_diagnostics(self):
        workflow = WORKFLOW.read_text()
        step = workflow.split('      - name: Record Android validation outcome\n', 1)[1]
        step = step.split('      - name:', 1)[0]
        self.assertIn('        if: always()', step)
        script = textwrap.dedent(step.split('        run: |\n', 1)[1])
        for failed_step in ('checkout', 'regression_tests', 'java', 'flutter', 'setup'):
            for status in ('failure', 'cancelled'):
                with self.subTest(step=failed_step, status=status), tempfile.TemporaryDirectory() as temp:
                    steps = {
                        failed_step: {'outcome': status, 'conclusion': status,
                                      'outputs': {'synthetic_secret': 'excluded-output'}},
                        'graphs': {'outcome': 'skipped', 'conclusion': 'skipped'},
                    }
                    env = dict(os.environ, RUNNER_TEMP=temp, VALIDATION_JOB_STATUS=status,
                               VALIDATION_STEPS=json.dumps(steps), GITHUB_SHA='a' * 40,
                               GITHUB_RUN_ID='123', GITHUB_RUN_ATTEMPT='2')
                    # The script must work even when checkout failed.
                    subprocess.run(['bash', '-e', '-o', 'pipefail', '-c', script],
                                   cwd=temp, env=env, check=True, capture_output=True, text=True)
                    evidence = Path(temp) / 'neura-android-validation'
                    paths = list(evidence.glob('**/*.json'))
                    self.assertEqual([path.name for path in paths], ['job-outcome.json'])
                    raw = paths[0].read_text()
                    receipt = json.loads(raw)
                    self.assertEqual(receipt['kind'], 'job-diagnostics')
                    self.assertEqual(receipt['job_status'], status)
                    self.assertEqual(receipt['steps'][failed_step]['outcome'], status)
                    self.assertEqual(receipt['steps']['graphs']['outcome'], 'skipped')
                    self.assertEqual(receipt['event_sha'], 'a' * 40)
                    self.assertEqual(receipt['run_attempt'], '2')
                    self.assertNotIn('excluded-output', raw)
        self.assertIn('if-no-files-found: error', workflow)


if __name__ == '__main__':
    unittest.main()
