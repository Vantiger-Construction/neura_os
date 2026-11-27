#!/usr/bin/env python3
"""Run both pinned archive packages without editing the application lockfile.

Uses the branch's pinned Flutter SDK, full real plugin dependencies and fresh
fictional directories. No installed Neura process/store or model is used.
"""
import argparse
from contextlib import ExitStack
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from urllib.parse import urljoin

ROOT=Path(__file__).resolve().parents[2]
HASHES={
    '4.6.0':'de5ac590b8155e4e676088d714bd41ea620449a6adc0f7950c5073874b287ddb',
    '4.7.1':'2fda90592c0afd219c5e285618a98da835cd10df38372666093d25dfe457a2d0',
}

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flutter',default=shutil.which('flutter'))
    parser.add_argument('--output',default=str(ROOT/'build/legacy-zip-compatibility'))
    args=parser.parse_args()
    if not args.flutter:parser.error('The pinned Flutter executable is required.')
    flutter=Path(args.flutter).resolve()
    dart=flutter.parent/'cache/dart-sdk/bin'/('dart.exe' if os.name=='nt' else 'dart')
    output=Path(args.output).resolve()
    if output.exists():parser.error('Choose a fresh output directory to preserve previous results.')
    output.mkdir(parents=True)
    (output/'SYNTHETIC_ONLY').write_text('FICTIONAL ZIP MATRIX ONLY')
    pin=re.findall(r'^  FLUTTER_VERSION: [\'"]([0-9.]+)[\'"]\s*$',(ROOT/'.github/workflows/neura-coverage.yml').read_text(),re.M)
    if len(pin) != 1:
        raise RuntimeError('Expected exactly one branch Flutter pin.')
    version=subprocess.check_output([str(flutter),'--version','--machine'],cwd=ROOT,text=True)
    version_info=json.loads(version[version.index('{'):])
    if version_info['frameworkVersion']!=pin[0]:parser.error('Flutter must match the branch coverage pin.')
    lock_before=digest(ROOT/'pubspec.lock')
    frozen_fixtures = {}
    for version in HASHES:
        folder = ROOT/'test/legacy/fixtures'/('archive_'+version.replace('.', '_'))
        manifest = json.loads((folder/'manifest.json').read_text())
        if manifest['synthetic'] is not True or manifest['source_head'] != 'a0ca21c87a3b3713934b6e307cd98ae8dbda1eea':
            raise RuntimeError('Unexpected frozen fixture provenance.')
        if len(manifest['fixtures']) != 22:
            raise RuntimeError('Expected 22 frozen ZIP fixtures per producer.')
        for name, expected in manifest['fixtures'].items():
            if not re.fullmatch(r'[a-z0-9_]+\.zip', name) or digest(folder/name) != expected:
                raise RuntimeError('A frozen fictional fixture hash changed.')
        frozen_fixtures[version] = manifest['fixtures']
    config_path=ROOT/'.dart_tool/package_config.json'
    base=json.loads(config_path.read_text())
    base_graph=json.loads((config_path.parent/'package_graph.json').read_text())
    for package in base['packages']:
        package['rootUri']=urljoin(config_path.parent.as_uri()+'/',package['rootUri'])
    metadata={'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'flutter':version_info,
      'baseCommit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
      'indexTree':subprocess.check_output(['git','write-tree'],cwd=ROOT,text=True).strip(),
      'unstagedDiffSHA256':hashlib.sha256(subprocess.check_output(['git','diff','--binary'],cwd=ROOT)).hexdigest(),
      'syntheticOnly':True,'frozenFixtureSHA256':frozen_fixtures,'NeuraApplicationOrNativeDeviceTest':False,'packages':HASHES,'commands':[],'cells':[]}

    def run(command,label,cwd=ROOT,env=None):
        result=subprocess.run([str(c) for c in command],cwd=cwd,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=600)
        (output/(label+'.log')).write_text(result.stdout)
        metadata['commands'].append({'label':label,'exitCode':result.returncode})
        if result.returncode:
            (output/'results.json').write_text(json.dumps(metadata,indent=2))
            raise RuntimeError(label+' failed:\n'+result.stdout[-5000:])

    def directory(name):
        path=output/name;path.mkdir();(path/'SYNTHETIC_ONLY').write_text('FICTIONAL ZIP MATRIX ONLY');return path

    with tempfile.TemporaryDirectory(prefix='neura-synthetic-archive-packages-') as temp, ExitStack() as cleanup:
        work=Path(temp)
        env=dict(os.environ,PUB_CACHE=str(work/'pub-cache'),CI='true',FLUTTER_SUPPRESS_ANALYTICS='true')
        configs={}
        for version in HASHES:
            project=work/('archive_'+version);project.mkdir()
            (project/'pubspec.yaml').write_text('name: neura_zip_matrix_dependency\nenvironment:\n  sdk: ">=3.0.0 <4.0.0"\ndependencies:\n  archive: '+version+'\n')
            run([dart,'pub','get'],'resolve_'+version,cwd=project,env=env)
            package_path=project/'.dart_tool/package_config.json'
            package=json.loads(package_path.read_text())
            archive=next(p for p in package['packages'] if p['name']=='archive')
            cache_hash=work/'pub-cache/hosted-hashes/pub.dev'/('archive-'+version+'.sha256')
            if cache_hash.read_text().strip() != HASHES[version]:
                raise RuntimeError('The resolved archive package hash changed.')
            config=json.loads(json.dumps(base))
            replacement={**archive,'rootUri':urljoin(package_path.parent.as_uri()+'/',archive['rootUri'])}
            config['packages']=[replacement if p['name']=='archive' else p for p in config['packages']]
            config_directory = output/('dependency_'+version)
            config_directory.mkdir()
            path = config_directory/'package_config.json'
            path.write_text(json.dumps(config))
            graph = json.loads(json.dumps(base_graph))
            for package_entry in graph['packages']:
                if package_entry['name'] == 'archive':
                    package_entry['version'] = version
            (config_directory/'package_graph.json').write_text(json.dumps(graph))
            resolved_graph = json.loads((project/'.dart_tool/package_graph.json').read_text())
            expected_dependencies = next(p['dependencies'] for p in base_graph['packages'] if p['name'] == 'archive')
            actual_dependencies = next(p['dependencies'] for p in resolved_graph['packages'] if p['name'] == 'archive')
            if set(expected_dependencies) != set(actual_dependencies):
                raise RuntimeError('Archive changed its dependency graph; an isolated full resolution is required.')
            # Flutter native-assets code resolves ../pubspec.yaml from this
            # file. Keep the active copy beside the existing configuration;
            # neither the active config nor the application graph is changed.
            with tempfile.NamedTemporaryFile(mode='w', prefix='neura_zip_matrix_', suffix='.json', dir=config_path.parent, delete=False) as runtime_config:
                json.dump(config, runtime_config)
            runtime_path = Path(runtime_config.name)
            cleanup.callback(runtime_path.unlink, missing_ok=True)
            configs[version] = runtime_path

        def test(version,label,defines=None,script='tools/archive_compatibility/matrix_test.dart'):
            command=[flutter,'test','--no-pub','--concurrency','2','--timeout','2m','--packages',configs[version]]
            for name,value in (defines or {}).items():command+=['--dart-define='+name+'='+str(value)]
            run([*command,script],label)

        for version in HASHES:
            test(version,'legacy_regressions_'+version,script='test/legacy')
            test(version,'producer_'+version,{'NEURA_ZIP_MATRIX_OUTPUT':directory('exports_'+version),'NEURA_ZIP_MATRIX_PRODUCER':version})
        for producer in HASHES:
            for reader in HASHES:
                cell=directory('writer_'+producer+'_reader_'+reader)
                test(reader,cell.name,{'NEURA_ZIP_MATRIX_OUTPUT':cell,'NEURA_ZIP_MATRIX_INPUT':output/('exports_'+producer),'NEURA_ZIP_MATRIX_PRODUCER':producer,'NEURA_ZIP_MATRIX_READER':reader})
                metadata['cells'].append(json.loads((cell/'consumer.json').read_text()))
    if digest(ROOT/'pubspec.lock') != lock_before:
        raise RuntimeError('The application lockfile changed.')
    metadata['applicationLockfileUnchanged']=True
    (output/'results.json').write_text(json.dumps(metadata,indent=2))
    print(json.dumps({'versionPairsPassed':len(metadata['cells']),'ordinaryRestoreModesPassed':sum(len(c['results']) for c in metadata['cells']),'applicationLockfileUnchanged':True,'report':str(output/'results.json')}))

if __name__=='__main__':main()
