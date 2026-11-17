import copy
import json
from pathlib import Path
import tempfile
import unittest

from check_dependencies import MINIMUMS, TOOLCHAIN, compare, load_inventory, scan


class DependencyEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.old = self.root / 'old'
        self.new = self.root / 'new'
        self.output = self.root / 'output'
        for path in (self.old, self.new, self.output):
            path.mkdir()
        tooling = [dict(name=k, version=v + '-jre' if 'guava' in k else v) for k, v in MINIMUMS.items()]
        tooling.append(dict(name='org.bouncycastle:bcutil-jdk18on', version='1.87'))
        tooling.extend(dict(name=k, version=v) for k, v in TOOLCHAIN.items())
        self.app = dict(schema=1, status='complete', errors=[], build_root='/app/android',
                        build_name='android', gradle_version='9.9.1', projects=[':', ':app', ':flutter_tts'],
                        included_builds=['/sdk/flutter/gradle'], configurations=[],
                        distribution_libraries=[dict(file='lib/gradle-core-9.9.1.jar', modules=[])])
        for project in self.app['projects']:
            self.app['configurations'].append(dict(project=project, kind='buildscript', name='classpath',
                                                   modules=copy.deepcopy(tooling), projects=[]))
        for name in ('debugRuntimeClasspath', 'releaseRuntimeClasspath'):
            self.app['configurations'].append(dict(project=':app', kind='app-runtime', name=name,
                                                   modules=[dict(name='example:runtime', version='1.0')],
                                                   projects=['project :app', 'project :flutter_tts']))
        self.included = dict(schema=1, status='complete', errors=[], build_root='/sdk/flutter/gradle',
                             build_name='gradle', gradle_version='9.9.1', projects=[':'], included_builds=[],
                             configurations=[dict(project=':', kind='buildscript', name='classpath',
                                                  modules=[dict(name='example:plugin', version='2.0')], projects=[])],
                             distribution_libraries=[dict(file='lib/unmapped.jar', modules=[])])
        self.write(self.old)
        self.write(self.new)

    def write(self, directory):
        (directory / 'app.json').write_text(json.dumps(self.app))
        (directory / 'included.json').write_text(json.dumps(self.included))

    def test_unchanged_runtime_despite_tooling_update(self):
        report = compare(self.old, self.new)
        self.assertEqual(report['status'], 'runtime-unchanged')

    def test_release_runtime_and_project_drift_are_reported(self):
        config = self.app['configurations'][-1]
        config['modules'][0]['version'] = '2.0'
        config['projects'].append('project :unexpected')
        self.write(self.new)
        report = compare(self.old, self.new)
        self.assertEqual(report['status'], 'runtime-changed')
        self.assertIn('releaseRuntimeClasspath', report['changes'])

    def test_missing_included_build_is_incomplete(self):
        (self.new / 'included.json').unlink()
        with self.assertRaisesRegex(ValueError, 'included-build'):
            load_inventory(self.new)

    def test_missing_root_or_release_or_empty_inventory_is_incomplete(self):
        for kind, project in [('buildscript', ':'), ('app-runtime', ':app')]:
            original = copy.deepcopy(self.app)
            self.app['configurations'] = [c for c in self.app['configurations']
                                          if not (c['kind'] == kind and c['project'] == project)]
            self.write(self.new)
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                load_inventory(self.new)
            self.app = original
        with self.assertRaises(ValueError):
            load_inventory(self.output)

    def test_unresolved_and_duplicate_configuration_fail(self):
        for change in ('unresolved', 'duplicate'):
            original = copy.deepcopy(self.app)
            if change == 'unresolved':
                self.app.update(status='incomplete', errors=['could not resolve'])
            else:
                self.app['configurations'].append(self.app['configurations'][0])
            self.write(self.new)
            with self.subTest(change=change), self.assertRaises(ValueError):
                load_inventory(self.new)
            self.app = original

    def test_mixed_bouncy_castle_or_old_constraint_fail(self):
        for name in ('org.bouncycastle:bcutil-jdk18on', 'com.google.guava:guava'):
            original = copy.deepcopy(self.app)
            for config in self.app['configurations']:
                if config['kind'] == 'buildscript':
                    for module in config['modules']:
                        if module['name'] == name:
                            module['version'] = '1.85' if 'bouncycastle' in name else '33.7.2-jre'
            self.write(self.new)
            with self.subTest(name=name), self.assertRaises(ValueError):
                compare(self.old, self.new)
            self.app = original

    def test_queries_include_included_tooling_and_gradle_core(self):
        queries = []

        def clean(payload):
            queries.extend(payload['queries'])
            return dict(results=[{} for _ in payload['queries']])

        report = scan(self.new, self.output, clean)
        names = {q['package']['name'] for q in queries}
        self.assertTrue({'example:plugin', 'org.gradle:gradle-core'}.issubset(names))
        self.assertEqual(report['advisory_matches'], [])
        self.assertEqual(report['unmapped_distribution_jars'], ['lib/unmapped.jar'])

    def test_advisories_are_retained_and_pagination_is_completed(self):
        calls = []

        def paginated(payload):
            calls.append(payload)
            if len(calls) == 1:
                return dict(results=[dict(vulns=[dict(id='GHSA-first')], next_page_token='next')]
                            + [{} for _ in payload['queries'][1:]])
            self.assertEqual(payload['queries'][0]['page_token'], 'next')
            return dict(results=[dict(vulns=[dict(id='GHSA-second')])])

        report = scan(self.new, self.output, paginated)
        self.assertEqual(report['status'], 'findings')
        self.assertEqual({f['advisory'] for f in report['advisory_matches']}, {'GHSA-first', 'GHSA-second'})
        self.assertEqual(len(calls), 2)
        self.assertTrue((self.output / 'response-001.json').exists())

    def test_truncated_error_or_malformed_osv_responses_are_incomplete(self):
        for response in (dict(results=[]), dict(results='wrong'), {},
                         dict(results=[dict(error='unavailable')])):
            with self.subTest(response=response), self.assertRaises((ValueError, KeyError)):
                scan(self.new, self.output, lambda _: response)

    def test_repeated_pagination_token_fails(self):
        def repeated(payload):
            return dict(results=[dict(next_page_token='same') for _ in payload['queries']])

        with self.assertRaisesRegex(ValueError, 'pagination'):
            scan(self.new, self.output, repeated)

    def test_wrong_running_gradle_or_changed_kotlin_selection_fail(self):
        self.app['gradle_version'] = self.included['gradle_version'] = '9.8.2'
        self.write(self.new)
        with self.assertRaisesRegex(ValueError, 'Gradle 9.9.1'):
            compare(self.old, self.new)
        self.app['gradle_version'] = self.included['gradle_version'] = '9.9.1'
        for module in self.app['configurations'][0]['modules']:
            if module['name'] == 'org.jetbrains.kotlin:kotlin-gradle-plugin':
                module['version'] = '2.5.0'
        self.write(self.new)
        with self.assertRaisesRegex(ValueError, 'AGP/Kotlin'):
            compare(self.old, self.new)


if __name__ == '__main__':
    unittest.main()
