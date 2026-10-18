"""Offline tests of the actual recovery workflow blocks; no GitHub mutations."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

WORKFLOW = Path(__file__).resolve().parents[1] / '.github/workflows/neura-validation-recovery.yml'


def block(name, key):
    lines = WORKFLOW.read_text(encoding='utf-8').splitlines()
    start = lines.index('    - name: ' + name)
    for i in range(start + 1, len(lines)):
        if lines[i].lstrip().startswith(key + ': |'):
            indent = len(lines[i]) - len(lines[i].lstrip()) + 2
            result = []
            for line in lines[i + 1:]:
                if line.strip() and len(line) - len(line.lstrip()) < indent:
                    return '\n'.join(result)
                result.append(line[indent:])
            return '\n'.join(result)
    raise AssertionError('Missing workflow block: ' + name)


class RecoveryTest(unittest.TestCase):
    def test_retained_cmake_and_native_gate(self):
        if os.name != 'nt':
            self.skipTest('Windows CMake/MSVC native gate')
        source = block('Preflight retained CMake and the native Windows toolchain', 'script')
        action = Path(os.environ.get('NEURA_GITHUB_SCRIPT_ENTRY',
                                     'C:/actions-runner/_work/_actions/actions/github-script/v8/dist/index.js'))
        target = Path(os.environ.get('NEURA_NATIVE_CHECK_ROOT', str(WORKFLOW.parents[3] / 'pr136')))
        with tempfile.TemporaryDirectory(prefix='neura-cmake-probe-') as temporary:
            root = Path(temporary)
            for file in ['tools/offline_text_native_check/CMakeLists.txt',
                         'windows/runner/neura_local_conversation.cpp', 'windows/runner/neura_local_conversation.h']:
                destination = root / file
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(target / file, destination)
            for name in ['job-path', 'output']:
                (root / name).touch()
            env = dict(os.environ)
            for key in list(env):
                if key.upper() == 'PATH':
                    del env[key]
            env.update(PATH='C:/Windows/System32;C:/Windows', NEURA_SOURCE_ROOT=str(root),
                       RUNNER_TOOL_CACHE='C:/actions-runner/_work/_tool', GITHUB_PATH=str(root / 'job-path'),
                       GITHUB_OUTPUT=str(root / 'output'), GITHUB_REPOSITORY='example/offline',
                       LOCALAPPDATA='C:/Windows/ServiceProfiles/NetworkService/AppData/Local')
            env.update({'INPUT_SCRIPT':source, 'INPUT_GITHUB-TOKEN':'offline-unused-token', 'INPUT_DEBUG':'false',
                        'INPUT_USER-AGENT':'offline-test', 'INPUT_RESULT-ENCODING':'json',
                        'INPUT_RETRIES':'0', 'INPUT_RETRY-EXEMPT-STATUS-CODES':'400,401,403,404,422'})
            node = 'C:/actions-runner/externals/node24/bin/node.exe'
            result = subprocess.run([node, str(action)], env=env, capture_output=True, text=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            selected = (root / 'job-path').read_text().strip()
            env['PATH'] = selected + ';' + env['PATH']
            where = str(Path(os.environ['SystemRoot']) / 'System32/where.exe')
            cmake = subprocess.check_output([where, 'cmake'], env=env, text=True).splitlines()[0]
            result = subprocess.run([cmake, '--build', str(root / 'build/offline-native-check'), '--config', 'Release'],
                                    env=env, capture_output=True, text=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            cache = (root / 'build/offline-native-check/CMakeCache.txt').read_text()
            self.assertIn('CMAKE_GENERATOR:INTERNAL=Visual Studio 18 2026', cache)
            for mode in ['discovery_failed', 'discovery_empty', 'old', 'invalid', 'configure_failed']:
                (root / 'job-path').write_text('')
                injection = r'''
const real=require('child_process').spawnSync;
require('child_process').spawnSync=(file,args,options)=>{
  if(file.endsWith('vswhere.exe') && MODE==='discovery_failed') return {status:7,stdout:'C:/plausible',stderr:''};
  if(file.endsWith('vswhere.exe') && MODE==='discovery_empty') return {status:0,stdout:'',stderr:''};
  if(args[0]==='-E' && ['old','invalid'].includes(MODE)) return {status:0,stdout:JSON.stringify({version:MODE==='old'?{major:3,minor:13}:{}})};
  if(args[0]==='-S' && MODE==='configure_failed') return {status:7,stdout:'configuration failed',stderr:''};
  return real(file,args,options);
};
'''.replace('MODE', json.dumps(mode))
                env['INPUT_SCRIPT'] = injection + source
                result = subprocess.run([node, str(action)], env=env, capture_output=True, text=True, timeout=90)
                self.assertNotEqual(result.returncode, 0, mode + result.stdout + result.stderr)
                self.assertEqual((root / 'job-path').read_text(), '', mode)

    def test_retained_pwsh_and_pinned_installer_wrapper(self):
        if os.name != 'nt':
            self.skipTest('Windows PowerShell installer contract')
        source = block('Discover retained PowerShell 7 for the pinned coverage installer', 'script')
        self.assertNotIn('LOCALAPPDATA', source)
        action = Path(os.environ.get('NEURA_GITHUB_SCRIPT_ENTRY',
                                     'C:/actions-runner/_work/_actions/actions/github-script/v8/dist/index.js'))
        installer = Path('C:/actions-runner/_work/_actions/taiki-e/install-action/ab6895351a88b908e96a4697860d4ffea5e57dbe/action.yml')
        body = installer.read_text().split('    - run: |\n')[-1].split('      shell: pwsh')[0]
        wrapper = '\n'.join(line[8:] for line in body.splitlines())
        with tempfile.TemporaryDirectory(prefix='neura-pwsh-probe-') as temporary:
            root = Path(temporary)
            for name in ['job-path', 'output']:
                (root / name).touch()
            env = dict(os.environ)
            for key in list(env):
                if key.upper() == 'PATH':
                    del env[key]
            env.update(PATH='C:/Program Files/Git/bin;C:/Program Files/Git/usr/bin;C:/Windows/System32;C:/Windows',
                       GITHUB_PATH=str(root / 'job-path'), GITHUB_OUTPUT=str(root / 'output'),
                       GITHUB_REPOSITORY='example/offline',
                       LOCALAPPDATA='C:/Windows/ServiceProfiles/NetworkService/AppData/Local')
            env.update({'INPUT_SCRIPT':source, 'INPUT_GITHUB-TOKEN':'offline-unused-token', 'INPUT_DEBUG':'false',
                        'INPUT_USER-AGENT':'offline-test', 'INPUT_RESULT-ENCODING':'json',
                        'INPUT_RETRIES':'0', 'INPUT_RETRY-EXEMPT-STATUS-CODES':'400,401,403,404,422'})
            node = 'C:/actions-runner/externals/node24/bin/node.exe'
            result = subprocess.run([node, str(action)], env=env, capture_output=True, text=True, timeout=90)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            selected = (root / 'job-path').read_text().strip()
            env['PATH'] = selected + ';' + env['PATH']
            where = str(Path(os.environ['SystemRoot']) / 'System32/where.exe')
            pwsh = subprocess.check_output([where, 'pwsh'], env=env, text=True).splitlines()[0]
            (root / 'wrapper.ps1').write_text("$ErrorActionPreference = 'stop'\n" + wrapper)
            # Use the exact pinned wrapper; replace only its downloaded installer payload.
            (root / 'main.sh').write_text('''#!/usr/bin/env bash
set -eu
for name in ENV BASH_ENV CDPATH SHELLOPTS BASHOPTS; do
  if env | grep -q "^${name}="; then exit 31; fi
done
profile=$(cygpath -u "$USERPROFILE")
mkdir -p "$profile/.install-action"
touch "$profile/.install-action/init"
exit "$TEST_INSTALL_EXIT"
''')
            env.update(USERPROFILE=str(root), GITHUB_ACTION_PATH=str(root), INPUT_TOOL='cargo-llvm-cov@0.9.1',
                       INPUT_CHECKSUM='true', INPUT_FALLBACK='cargo-binstall', ENV='must-be-removed',
                       BASH_ENV='must-be-removed', CDPATH='must-be-removed')
            for code in [0, 7]:
                env['TEST_INSTALL_EXIT'] = str(code)
                result = subprocess.run([pwsh, '-NoLogo', '-NoProfile', '-NonInteractive', '-Command',
                                         ". '" + str(root / 'wrapper.ps1').replace("'", "''") + "'"],
                                        env=env, capture_output=True, text=True, timeout=60)
                if code == 0:
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                else:
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertFalse((root / '.install-action/init').exists())
            for mode in ['nonzero', 'unsigned', 'old', 'missing']:
                (root / 'job-path').write_text('')
                runtime = dict(path=pwsh, major=7, edition='Core', version='7.6.7', signature='Valid', signer='O=Microsoft Corporation')
                if mode == 'unsigned':
                    runtime['signature'] = 'NotSigned'
                if mode == 'old':
                    runtime['major'] = 5
                if mode == 'missing':
                    runtime['path'] = str(root / 'missing.exe')
                injection = "require('child_process').spawnSync=()=>({status:" + ('7' if mode == 'nonzero' else '0') + ",stdout:" + json.dumps(json.dumps(runtime)) + "});\n"
                env['INPUT_SCRIPT'] = injection + source
                result = subprocess.run([node, str(action)], env=env, capture_output=True, text=True, timeout=30)
                self.assertNotEqual(result.returncode, 0, mode + result.stdout + result.stderr)
                self.assertEqual((root / 'job-path').read_text(), '')

    def test_coverage_junction_paths_and_measurement_gates(self):
        source = block('Normalize measured Flutter source paths', 'script')
        self.assertEqual(source, block('Normalize measured Rust source paths', 'script'))
        with tempfile.TemporaryDirectory(prefix='neura-coverage-paths-') as temporary:
            root = Path(temporary)
            (root / 'source.json').write_text(json.dumps(source))
            harness = r'''
const fs=require('fs'), path=require('path'), assert=require('assert');
const code=JSON.parse(fs.readFileSync(path.join(__dirname,'source.json')));
const AsyncFunction=Object.getPrototypeOf(async function(){}).constructor;
const run=new AsyncFunction('require','process','core',code);
const scoped=new Function('require',code.split('const logical = process.env.')[0]+'return scopedSource;')(require);
for(const api of [path.win32,path.posix]) {
  const win=api===path.win32;
  const logical=win?'C:/actions-runner/_work/neura_os/neura_os/recovery':'/actions-runner/_work/neura_os/neura_os/recovery';
  const physical=win?'C:/neura-ci/run/workspace':'/neura-ci/run/workspace';
  const relative='../../../../../neura-ci/run/workspace/lib/main.dart';
  const source=api.join(physical,'lib/main.dart');
  const resolve=p=>p.startsWith(api.normalize(logical))?api.join(physical,api.relative(logical,p)):p;
  for(const value of [relative, win?relative.replace(/\//g,'\\'):relative, 'lib/main.dart',source])
    assert.equal(scoped(value,logical,physical,api,resolve),'lib/main.dart');
  for(const value of ['../lib/main.dart',physical+'-other/lib/main.dart','/external/lib/main.dart','lib/../../outside.dart'])
    assert.equal(scoped(value,logical,physical,api,resolve),null,value);
  assert.equal(scoped('lib/link.dart',logical,physical,api,()=>api.resolve(physical,'../outside.dart')),null);
  for(const value of [api.join(logical,'rust/src/engine_session.rs'), logical+'/rust/tests/../src/engine_session.rs',
                     api.join(physical,'rust/src/engine_session.rs')])
    assert.equal(scoped(value,logical,physical,api,resolve,'rust'),'rust/src/engine_session.rs');
  for(const value of [physical+'-sibling/rust/src/a.rs', '/registry/src/a.rs', 'rust/tests/lifecycle.rs'])
    assert.equal(scoped(value,logical,physical,api,resolve,'rust'),null);
}
(async()=>{
  const physical=path.join(__dirname,'neura-ci/run/workspace');
  const logical=path.join(__dirname,'a/b/c/d/link');
  fs.mkdirSync(path.join(physical,'lib'),{recursive:true});
  fs.mkdirSync(path.join(physical,'coverage/flutter'),{recursive:true});
  fs.mkdirSync(path.dirname(logical),{recursive:true});
  fs.symlinkSync(physical,logical,'junction');
  fs.writeFileSync(path.join(physical,'lib/main.dart'),'// synthetic source');
  fs.mkdirSync(path.join(__dirname,'outside'));
  fs.writeFileSync(path.join(__dirname,'outside/secret.dart'),'// excluded source');
  fs.symlinkSync(path.join(__dirname,'outside'),path.join(physical,'lib/escape'),'junction');
  const measured='SF:..\\..\\..\\..\\..\\neura-ci\\run\\workspace\\lib\\main.dart\r\nDA:1,0\r\nDA:2,7\r\nend_of_record\r\n';
  const raw=measured+'SF:lib/escape/secret.dart\r\nDA:99,100\r\nend_of_record\r\n';
  const file=path.join(physical,'coverage/flutter/raw.lcov.info');
  fs.writeFileSync(file,raw);
  await run(require,{env:{NEURA_SOURCE_ROOT:logical,NEURA_EXPECTED_HEAD:'b'.repeat(40),NEURA_WORKFLOW_COMMIT:'a'.repeat(40)}},{info(){}});
  assert.equal(fs.readFileSync(file,'utf8'),raw);
  const normalized=fs.readFileSync(path.join(physical,'coverage/flutter/normalized.lcov.info'),'utf8');
  assert.equal(normalized,'SF:lib/main.dart\r\n'+measured.split('\r\n').slice(1).join('\r\n')+'SF:__excluded_by_containment__/source\r\nDA:99,100\r\nend_of_record\r\n');
  fs.writeFileSync(path.join(__dirname,'normalized.info'),normalized);
  fs.mkdirSync(path.join(physical,'rust/src'),{recursive:true});
  fs.mkdirSync(path.join(physical,'rust/tests'),{recursive:true});
  fs.mkdirSync(path.join(physical,'coverage/rust-windows'),{recursive:true});
  for(const file of ['src/engine_session.rs','src/frb_generated.rs','tests/lifecycle.rs'])
    fs.writeFileSync(path.join(physical,'rust',file),'// synthetic Rust source');
  const rustRaw=`SF:${path.join(logical,'rust/src/engine_session.rs')}\nDA:1,0\nDA:2,0\nend_of_record\n`+
    `SF:${logical}/rust/tests/../src/engine_session.rs\nDA:1,3\nend_of_record\n`+
    `SF:${logical}/rust/src/frb_generated.rs\nDA:1,7\nend_of_record\n`+
    `SF:${logical}/rust/tests/lifecycle.rs\nDA:1,7\nend_of_record\n`+
    'SF:C:/registry/dependency/src/lib.rs\nDA:1,9\nend_of_record\n';
  const rustInput=path.join(physical,'coverage/rust-windows/raw.lcov.info');
  fs.writeFileSync(rustInput,rustRaw);
  await run(require,{env:{NEURA_SOURCE_ROOT:logical,NEURA_COVERAGE_LANGUAGE:'rust'}},{info(){}});
  const rustNormalized=fs.readFileSync(path.join(physical,'coverage/rust-windows/normalized.lcov.info'),'utf8');
  assert.equal(fs.readFileSync(rustInput,'utf8'),rustRaw);
  assert.deepEqual(rustNormalized.split('\n').filter(x=>!x.startsWith('SF:')),rustRaw.split('\n').filter(x=>!x.startsWith('SF:')));
  fs.writeFileSync(path.join(__dirname,'rust-normalized.info'),rustNormalized);
  for(const content of ['', 'SF:../external.dart\nDA:1,1\nend_of_record']) {
    fs.writeFileSync(file,content);
    await assert.rejects(run(require,{env:{NEURA_SOURCE_ROOT:logical}},{info(){}}),/no verified checkout/);
  }
})().catch(e=>{console.error(e);process.exitCode=1});
'''
            script = root / 'test.cjs'
            script.write_text(harness)
            result = subprocess.run(['C:/actions-runner/externals/node24/bin/node.exe', str(script)],
                                    capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            import importlib.util
            spec = importlib.util.spec_from_file_location('coverage_report', WORKFLOW.parents[2] / 'tools/coverage/report.py')
            report = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(report)
            self.assertEqual(report.parse_lcov((root / 'normalized.info').read_text(), str(root), 'flutter'),
                             {'lib/main.dart': {1: 0, 2: 7}})
            self.assertEqual(report.parse_lcov((root / 'rust-normalized.info').read_text(), str(root), 'rust'),
                             {'rust/src/engine_session.rs': {1: 3, 2: 0}})
            for invalid in ['', 'SF:lib/main.dart\nend_of_record', 'SF:lib/main.dart\nDA:1,-1\nend_of_record',
                            'SF:lib/main.dart\nDA:1,1']:
                with self.assertRaises(ValueError):
                    report.parse_lcov(invalid, str(root), 'flutter')
                with self.assertRaises(ValueError):
                    report.parse_lcov(invalid.replace('lib/main.dart', 'rust/src/main.rs'), str(root), 'rust')

    def test_retained_bash_discovery(self):
        if os.name != 'nt':
            self.skipTest('Windows Git Bash discovery')
        source = block('Discover and enable retained Git Bash', 'script')
        node = Path('C:/actions-runner/externals/node24/bin/node.exe')
        action = Path(os.environ.get('NEURA_GITHUB_SCRIPT_ENTRY',
                                     'C:/actions-runner/_work/_actions/actions/github-script/v8/dist/index.js'))
        self.assertTrue(node.is_file() and action.is_file(), 'Retained Node 24 and github-script v8 required')
        with tempfile.TemporaryDirectory(prefix='neura-bash-probe-') as temporary:
            root = Path(temporary)
            (root / 'job-path').touch()
            (root / 'output').touch()
            env = dict(os.environ)
            for key in list(env):
                if key.upper() == 'PATH':
                    del env[key]
            env.update(PATH='C:/Program Files/Git/cmd;C:/Windows/System32;C:/Windows',
                       NEURA_SOURCE_ROOT=str(root), GITHUB_PATH=str(root / 'job-path'),
                       GITHUB_OUTPUT=str(root / 'output'), GITHUB_REPOSITORY='example/offline')
            env.update({'INPUT_SCRIPT':source, 'INPUT_GITHUB-TOKEN':'offline-unused-token', 'INPUT_DEBUG':'false',
                        'INPUT_USER-AGENT':'offline-test', 'INPUT_RESULT-ENCODING':'json',
                        'INPUT_RETRIES':'0', 'INPUT_RETRY-EXEMPT-STATUS-CODES':'400,401,403,404,422'})
            where = str(Path(os.environ['SystemRoot']) / 'System32/where.exe')
            self.assertNotEqual(subprocess.run([where, 'bash'], env=env, capture_output=True).returncode, 0)
            result = subprocess.run([str(node), str(action)], env=env, capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            entries = (root / 'job-path').read_text().splitlines()
            self.assertEqual(entries, [r'C:\Program Files\Git\usr\bin', r'C:\Program Files\Git\bin'])
            env['PATH'] = ';'.join(reversed(entries)) + ';' + env['PATH']
            shell = subprocess.check_output([where, 'bash'], env=env, text=True).splitlines()[0]
            result = subprocess.run([shell, '--noprofile', '--norc', '-e', '-o', 'pipefail', '-c',
                                     'for tool in bash git grep tee mkdir; do command -v "$tool" || exit 17; done'],
                                    env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            # Exercise the same action invocation with injected native process results.
            for mode in ['missing', 'nonzero', 'marker', 'timeout', 'where']:
                (root / 'job-path').write_text('')
                injection = """
const cp = require('child_process');
cp.spawnSync = (file) => file.endsWith('where.exe')
  ? {status: MODE === 'where' ? 1 : 0, stdout: MODE === 'missing' ? 'C:/absent/cmd/git.exe' : 'C:/Program Files/Git/cmd/git.exe', stderr:''}
  : {status: MODE === 'nonzero' ? 7 : MODE === 'timeout' ? null : 0,
     stdout: MODE === 'marker' ? '' : 'NEURA_BASH_OK\\n', stderr:'',
     error: MODE === 'timeout' ? new Error('ETIMEDOUT') : undefined};
""".replace('MODE', json.dumps(mode))
                env['INPUT_SCRIPT'] = injection + source
                result = subprocess.run([str(node), str(action)], env=env, capture_output=True, text=True, timeout=30)
                self.assertNotEqual(result.returncode, 0, mode + result.stdout + result.stderr)
                self.assertEqual((root / 'job-path').read_text(), '', mode)

    def test_retained_python_success_and_failures(self):
        if os.name != 'nt':
            self.skipTest('Windows PowerShell native-exit contract')
        source = block('Use a compatible retained Python runtime for reports', 'run')
        function = source.split('$candidates = @(')[0]
        with tempfile.TemporaryDirectory(prefix='neura-python-probe-') as temporary:
            root = Path(temporary)
            # A native fixture reports plausible JSON even when its exit is nonzero.
            script = function + r'''
$fixture = Join-Path $PSScriptRoot 'probe.exe'
Add-Type -OutputAssembly $fixture -OutputType ConsoleApplication -TypeDefinition @'
using System;
public class Probe {
  public static int Main() {
    string p = System.Reflection.Assembly.GetExecutingAssembly().Location.Replace("\\", "\\\\");
    Console.WriteLine("{\"path\":\"" + p + "\",\"version\":[3," + Environment.GetEnvironmentVariable("TEST_MINOR") + ",4]}");
    return Int32.Parse(Environment.GetEnvironmentVariable("TEST_EXIT"));
  }
}
'@
$env:TEST_MINOR = '14'
$env:TEST_EXIT = '7'
try { $null = Find-ReportPython @($fixture); throw 'accepted failing probe' }
catch { if ($_.Exception.Message -notlike 'No compatible*') { throw } }
$env:TEST_MINOR = '10'
$env:TEST_EXIT = '0'
try { $null = Find-ReportPython @($fixture); throw 'accepted unsupported version' }
catch { if ($_.Exception.Message -notlike 'No compatible*') { throw } }
try { $null = Find-ReportPython @((Join-Path $PSScriptRoot 'missing.exe')); throw 'accepted missing interpreter' }
catch { if ($_.Exception.Message -notlike 'No compatible*') { throw } }
$env:TEST_MINOR = '14'
$runtime = Find-ReportPython @($fixture)
if ($runtime.version[1] -ne 14) { throw 'wrong fixture version' }
$runtime = Find-ReportPython @('C:\Python314\python.exe')
if ($runtime.version[1] -ne 14) { throw 'wrong installed version' }
'''
            file = root / 'test.ps1'
            file.write_text(script, encoding='utf-8')
            command = [str(Path(os.environ['SystemRoot']) / 'System32/WindowsPowerShell/v1.0/powershell.exe'),
                       '-NoProfile', '-NonInteractive', '-File', str(file)]
            result = subprocess.run(command, capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_report_fallback_and_delivery_failures(self):
        if not shutil.which('node'):
            self.fail('Node is required to test actions/github-script blocks')
        source = block('Preserve bounded reports as private draft assets if artifact storage fails', 'script')
        gate = block('Require verified evidence delivery', 'script')
        with tempfile.TemporaryDirectory(prefix='neura-report-fallback-') as temporary:
            root = Path(temporary)
            (root / 'fallback.json').write_text(json.dumps(source), encoding='utf-8')
            (root / 'gate.json').write_text(json.dumps(gate), encoding='utf-8')
            harness = r'''
const fs = require('fs'), path = require('path'), assert = require('assert');
const AsyncFunction = Object.getPrototypeOf(async function(){}).constructor;
const code = JSON.parse(fs.readFileSync(path.join(__dirname,'fallback.json')));
const gate = new AsyncFunction('core','process',JSON.parse(fs.readFileSync(path.join(__dirname,'gate.json'))));
const run = new AsyncFunction('require','process','context','github','core',code);
const head = 'b'.repeat(40);
async function scenario(name, mode, expected) {
  let root = path.join(__dirname, name);
  const coverage = path.join(root,'coverage');
  fs.mkdirSync(coverage,{recursive:true});
  if(mode==='junction') {
    const logical=path.join(__dirname,'a',name,'b/c/link');
    fs.mkdirSync(path.dirname(logical),{recursive:true}); fs.symlinkSync(root,logical,'junction'); root=logical;
  }
  const receipt = {expected_head:head,tested_head:head,target_pr:133,run_id:123,run_attempt:'1',
    suite_outcomes:{flutter:'failure',rust:'skipped'},head_still_current:true};
  if (mode === 'identity') receipt.tested_head = 'c'.repeat(40);
  if (mode !== 'missing') fs.writeFileSync(path.join(coverage,'validation-receipt.json'),JSON.stringify(receipt));
  fs.writeFileSync(path.join(coverage,'secret.txt'),'must not be read or uploaded');
  if (['reports','oversize','linked','junction','empty_lcov'].includes(mode)) {
    fs.mkdirSync(path.join(root,'lib'),{recursive:true});
    fs.writeFileSync(path.join(root,'lib/main.dart'),'// synthetic source');
    fs.mkdirSync(path.join(coverage,'flutter'));
    const measured=mode==='junction'?path.relative(root,path.join(path.dirname(coverage),'lib/main.dart')):root.replace(/\\/g,'/')+'/lib/main.dart';
    fs.writeFileSync(path.join(coverage,'flutter/raw.lcov.info'), mode==='empty_lcov'?'SF:C:/private/secret.dart\nDA:1,0\nend_of_record\n':`SF:${measured}\nDA:1,1\nend_of_record\nSF:C:/private/secret.dart\nDA:1,0\nend_of_record\nSF:${path.dirname(coverage)}-sibling/lib/main.dart\nDA:1,0\nend_of_record\n`);
    fs.writeFileSync(path.join(coverage,'flutter/summary.json'),'{}');
    if(mode==='reports' || mode==='junction') {
      fs.mkdirSync(path.join(root,'rust/src'),{recursive:true});
      fs.writeFileSync(path.join(root,'rust/src/engine_session.rs'),'// synthetic source');
      fs.mkdirSync(path.join(coverage,'rust-windows'));
      fs.writeFileSync(path.join(coverage,'rust-windows/raw.lcov.info'),
        `SF:${root}/rust/tests/../src/engine_session.rs\nDA:1,2\nend_of_record\nSF:C:/registry/src/lib.rs\nDA:1,99\nend_of_record\n`);
      fs.writeFileSync(path.join(coverage,'rust-windows/path-provenance.json'),'{}');
    }
    if (mode === 'oversize') fs.writeFileSync(path.join(coverage,'flutter/summary.json'),Buffer.alloc(16*1024*1024+1));
    if (mode === 'linked') {
      const outside = path.join(__dirname,'outside'); fs.mkdirSync(outside,{recursive:true});
      fs.symlinkSync(outside,path.join(coverage,'rust-windows'),'junction');
    }
  }
  const uploads = [], creates = [];
  const github = {rest:{repos:{
    get: async()=>({data:{full_name:'Vantiger-Construction/neura_os',private:mode !== 'public'}}),
    createRelease:async args=>{creates.push(args); if(mode==='api')throw Error('API unavailable'); return {data:{id:1,draft:true,prerelease:true,html_url:'https://example.invalid/draft'}};},
    uploadReleaseAsset:async args=>{uploads.push(args);return {data:{id:uploads.length}};},
    getReleaseAsset:async args=>({data: mode==='checksum' ? Buffer.from('wrong') : uploads[args.asset_id-1].data})
  }}};
  const summary = {addHeading(){return this},addLink(){return this},addRaw(){return this},async write(){}};
  const env = {NEURA_SOURCE_ROOT:root,NEURA_TARGET_PR:'133',NEURA_EXPECTED_HEAD:head,GITHUB_RUN_ATTEMPT:'1',NEURA_WORKFLOW_COMMIT:'a'.repeat(40)};
  let failed = false;
  try {await run(require,{env},{repo:{owner:'Vantiger-Construction',repo:'neura_os'},runId:123},github,{summary});}
  catch(e) {failed=true; if(!expected)throw e;}
  assert.equal(failed,expected,name);
  assert(fs.existsSync(path.join(coverage,'secret.txt')));
  assert(!uploads.some(x=>x.name==='secret.txt'));
  if(!expected) {
    assert(creates[0].draft && creates[0].prerelease);
    const saved = JSON.parse(uploads.find(x=>x.name==='validation-receipt.json').data);
    assert.equal(saved.suite_outcomes.flutter,'failure');
    assert.equal(saved.suite_outcomes.rust,'skipped');
    const manifest = JSON.parse(uploads.find(x=>x.name==='report-manifest.json').data);
    assert.equal(manifest.head,head); assert(manifest.missing.length > 0);
    if(mode==='reports' || mode==='junction') {
      const lcov=uploads.find(x=>x.name==='flutter-raw.lcov.info').data.toString();
      assert(lcov.includes('SF:lib/main.dart')); assert(!lcov.includes('private')); assert(!lcov.includes('DA:1,0'));
      const rust=uploads.find(x=>x.name==='rust-windows-raw.lcov.info').data.toString();
      assert(rust.includes('SF:rust/src/engine_session.rs')); assert(rust.includes('DA:1,2'));
      assert(!rust.includes('registry')); assert(!rust.includes('DA:1,99'));
      assert(uploads.some(x=>x.name==='rust-windows-path-provenance.json'));
    }
  }
  console.log('PASS '+name);
}
(async()=>{
  for(const mode of ['partial','reports','junction','empty_lcov','missing','identity','oversize','linked','public','api','checksum'])
    await scenario(mode,mode,!['partial','reports','junction'].includes(mode));
  for(const [artifact,fallback,fail] of [['success','skipped',false],['failure','success',false],['failure','failure',true],['skipped','skipped',true]]) {
    let rejected=false; await gate({setFailed(){rejected=true}},{env:{ARTIFACT_OUTCOME:artifact,FALLBACK_OUTCOME:fallback}});
    assert.equal(rejected,fail);
  }
  console.log('PASS delivery gates');
})().catch(e=>{console.error(e);process.exitCode=1});
'''
            file = root / 'test.cjs'
            file.write_text(harness, encoding='utf-8')
            result = subprocess.run(['node', str(file)], capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
