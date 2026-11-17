"""Compare resolved Android graphs and query OSV; incomplete evidence fails closed."""

import argparse
import datetime
import hashlib
import json
from pathlib import Path
import re
import sys
import urllib.request


OSV_URL = 'https://api.osv.dev/v1/querybatch'
IGNORED_TOOLING_ADVISORIES = {'org.tomlj:tomlj'}
MINIMUMS = {
    'com.google.guava:guava': '33.8.0',
    'org.apache.commons:commons-lang3': '3.22.0',
    'org.bitbucket.b_c:jose4j': '0.9.7',
    'org.bouncycastle:bcpkix-jdk18on': '1.87',
    'org.bouncycastle:bcprov-jdk18on': '1.87',
}
TOOLCHAIN = {'com.android.tools.build:gradle': '9.5.1',
             'org.jetbrains.kotlin:kotlin-gradle-plugin': '2.4.21'}


def modules(values):
    result = set()
    seen = {}
    for item in values:
        name, version = item['name'], item['version']
        if (not isinstance(name, str) or name.count(':') != 1 or
                not isinstance(version, str) or not version or
                re.search(r'[\[\](),+*\s]', version)):
            raise ValueError('Invalid or unresolved Maven coordinate')
        if name in seen and seen[name] != version:
            raise ValueError('Conflicting versions in one resolved configuration: ' + name)
        seen[name] = version
        result.add((name, version))
    return result


def load_inventory(directory):
    builds = {}
    inputs = {}
    for path in sorted(directory.glob('*.json')):
        report = json.loads(path.read_text())
        if report['schema'] != 1 or report['status'] != 'complete' or report['errors']:
            raise ValueError('Incomplete Gradle inventory: ' + path.name)
        key = report['build_root']
        if key in builds:
            raise ValueError('Duplicate build inventory')
        builds[key] = report
        inputs[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
        configs = report['configurations']
        identities = {(c['project'], c['kind'], c['name']) for c in configs}
        if len(identities) != len(configs):
            raise ValueError('Duplicate configuration inventory')
        covered = {c['project'] for c in configs if c['kind'] == 'buildscript'}
        if covered != set(report['projects']) or ':' not in covered:
            raise ValueError('Missing root/project buildscript coverage')
        for config in configs:
            modules(config['modules'])
        if not report['distribution_libraries']:
            raise ValueError('Missing Gradle distribution library inventory')
    if not builds:
        raise ValueError('Empty Gradle inventory')
    if len({b['gradle_version'] for b in builds.values()}) != 1:
        raise ValueError('Build inventories disagree on the running Gradle version')
    for build in builds.values():
        if not set(build['included_builds']).issubset(builds):
            raise ValueError('Missing included-build inventory')
    mains = [b for b in builds.values() if any(c['kind'] == 'app-runtime' for c in b['configurations'])]
    if len(mains) != 1 or not mains[0]['included_builds']:
        raise ValueError('Expected one Android app and its included Flutter tooling build')
    runtime = {c['name']: c for c in mains[0]['configurations'] if c['kind'] == 'app-runtime'}
    if set(runtime) != {'debugRuntimeClasspath', 'releaseRuntimeClasspath'}:
        raise ValueError('Missing debug/release application runtime coverage')
    if any(not modules(c['modules']) for c in runtime.values()):
        raise ValueError('Empty application runtime graph')
    return builds, mains[0], inputs


def version_key(value):
    match = re.fullmatch(r'(\d+(?:\.\d+)*)(?:-jre|-android)?', value)
    if not match:
        raise ValueError('Re-audit non-release tooling version: ' + value)
    return tuple(int(part) for part in match[1].split('.'))


def compare(baseline, candidate):
    _, old, old_inputs = load_inventory(baseline)
    _, new, new_inputs = load_inventory(candidate)
    if new['gradle_version'] != '9.9.1':
        raise ValueError('Candidate was not inventoried with Gradle 9.9.1')
    if old['projects'] != new['projects']:
        raise ValueError('Android plugin project set changed')
    changes = {}
    for name in ('debugRuntimeClasspath', 'releaseRuntimeClasspath'):
        before = next(c for c in old['configurations'] if c['kind'] == 'app-runtime' and c['name'] == name)
        after = next(c for c in new['configurations'] if c['kind'] == 'app-runtime' and c['name'] == name)
        removed = sorted(modules(before['modules']) - modules(after['modules']))
        added = sorted(modules(after['modules']) - modules(before['modules']))
        if removed or added or sorted(before['projects']) != sorted(after['projects']):
            changes[name] = dict(removed=removed, added=added,
                                 previous_projects=before['projects'], candidate_projects=after['projects'])
    selected = set()
    toolchain_selected = set()
    for config in new['configurations']:
        if config['kind'] != 'buildscript':
            continue
        resolved = dict(modules(config['modules']))
        for name, version in TOOLCHAIN.items():
            if name in resolved:
                toolchain_selected.add(name)
                if resolved[name] != version:
                    raise ValueError('AGP/Kotlin selection changed: ' + name)
        if config['project'] == ':':
            continue
        for name, minimum in MINIMUMS.items():
            if name in resolved:
                selected.add(name)
                if version_key(resolved[name]) < version_key(minimum):
                    raise ValueError('Tooling minimum not selected: ' + name)
        bc = {version for name, version in resolved.items()
              if name in {'org.bouncycastle:bcpkix-jdk18on', 'org.bouncycastle:bcprov-jdk18on',
                          'org.bouncycastle:bcutil-jdk18on'}}
        if bc and (len(bc) != 1 or version_key(next(iter(bc))) < version_key('1.87')):
            raise ValueError('Bouncy Castle tooling modules are mixed or below 1.87')
    if selected != set(MINIMUMS):
        raise ValueError('Not all five updated tooling constraints were exercised')
    if toolchain_selected != set(TOOLCHAIN):
        raise ValueError('AGP/Kotlin selection was not inventoried')
    return dict(status='runtime-changed' if changes else 'runtime-unchanged', changes=changes,
                baseline_inputs=old_inputs, candidate_inputs=new_inputs,
                baseline_gradle=old['gradle_version'], candidate_gradle=new['gradle_version'])


def query(payload):
    request = urllib.request.Request(OSV_URL, json.dumps(payload).encode(),
                                     {'Content-Type': 'application/json',
                                      'User-Agent': 'Neura-Android-Dependency-Validation'})
    with urllib.request.urlopen(request, timeout=60) as response:
        raw = response.read(8 * 1024 * 1024 + 1)
    if len(raw) > 8 * 1024 * 1024:
        raise ValueError('OSV response exceeded evidence limit')
    return json.loads(raw)


def scan(directory, output, request=query):
    builds, _, inputs = load_inventory(directory)
    packages = set()
    ignored = set()
    unmapped = set()
    for build in builds.values():
        packages.add(('org.gradle:gradle-core', build['gradle_version']))
        for config in build['configurations']:
            for name, version in modules(config['modules']):
                if name in IGNORED_TOOLING_ADVISORIES:
                    ignored.add((name, version))
                    continue
                packages.add((name, version))
        for library in build['distribution_libraries']:
            for name, version in modules(library['modules']):
                if name in IGNORED_TOOLING_ADVISORIES:
                    ignored.add((name, version))
                    continue
                packages.add((name, version))
            if not library['modules'] and not Path(library['file']).name.startswith('gradle-'):
                unmapped.add(library['file'])
    findings = []
    ordered = sorted(packages)
    number = 0
    for offset in range(0, len(ordered), 100):
        pending = [(name, version, None) for name, version in ordered[offset:offset + 100]]
        tokens = set()
        for _ in range(20):
            queries = [dict(package=dict(ecosystem='Maven', name=name), version=version,
                            **({'page_token': token} if token else {})) for name, version, token in pending]
            payload = dict(queries=queries)
            (output / f'query-{number:03}.json').write_text(json.dumps(payload, indent=2) + '\n')
            response = request(payload)
            (output / f'response-{number:03}.json').write_text(json.dumps(response, indent=2) + '\n')
            number += 1
            results = response['results']
            if not isinstance(results, list) or len(results) != len(pending):
                raise ValueError('Incomplete OSV batch response')
            again = []
            for (name, version, _), result in zip(pending, results):
                if not isinstance(result, dict) or 'error' in result:
                    raise ValueError('OSV returned a package error')
                vulns = result.get('vulns', [])
                if not isinstance(vulns, list):
                    raise ValueError('Malformed OSV vulnerability list')
                for vuln in vulns:
                    if not isinstance(vuln['id'], str) or not vuln['id']:
                        raise ValueError('OSV advisory ID missing')
                    findings.append(dict(name=name, version=version, advisory=vuln['id']))
                token = result.get('next_page_token')
                if token:
                    identity = (name, version, token)
                    if not isinstance(token, str) or identity in tokens:
                        raise ValueError('OSV pagination did not advance')
                    tokens.add(identity)
                    again.append(identity)
            if not again:
                break
            pending = again
        else:
            raise ValueError('OSV pagination was not completed')
    findings = [entry for entry in findings if (entry['name'], entry['version']) not in ignored]
    return dict(status='findings' if findings else 'no-known-findings-in-inventoried-modules',
                queried_packages=len(packages), advisory_matches=findings, inputs=inputs,
                ignored_tooling_packages=sorted(f'{name}:{version}' for name, version in sorted(ignored)),
                unmapped_distribution_jars=sorted(unmapped),
                scope='Resolved app debug/release, root/project buildscript, included JVM tooling, '
                      'Gradle core and distribution JARs with Maven metadata. Unmapped JARs are '
                      'listed, not declared advisory-free. No reachability or device acceptance claim.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    comparison = commands.add_parser('compare')
    comparison.add_argument('--baseline', required=True, type=Path)
    comparison.add_argument('--candidate', required=True, type=Path)
    comparison.add_argument('--output', required=True, type=Path)
    audit = commands.add_parser('scan')
    audit.add_argument('--inventory', required=True, type=Path)
    audit.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    target = args.output if args.command == 'compare' else args.output / 'receipt.json'
    receipt = dict(status='incomplete', started_at=datetime.datetime.now(datetime.timezone.utc).isoformat())
    code = 2
    try:
        if args.command == 'compare':
            receipt.update(compare(args.baseline, args.candidate))
            code = 1 if receipt['changes'] else 0
        else:
            args.output.mkdir(parents=True, exist_ok=True)
            receipt.update(scan(args.inventory, args.output))
            code = 1 if receipt['advisory_matches'] else 0
    except (OSError, ValueError, KeyError, TypeError) as error:
        receipt['error'] = str(error)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(receipt, indent=2))
    return code


if __name__ == '__main__':
    sys.exit(main())
