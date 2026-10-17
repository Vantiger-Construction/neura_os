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
  const root = path.join(__dirname, name), coverage = path.join(root,'coverage');
  fs.mkdirSync(coverage,{recursive:true});
  const receipt = {expected_head:head,tested_head:head,target_pr:133,run_id:123,run_attempt:'1',
    suite_outcomes:{flutter:'failure',rust:'skipped'},head_still_current:true};
  if (mode === 'identity') receipt.tested_head = 'c'.repeat(40);
  if (mode !== 'missing') fs.writeFileSync(path.join(coverage,'validation-receipt.json'),JSON.stringify(receipt));
  fs.writeFileSync(path.join(coverage,'secret.txt'),'must not be read or uploaded');
  if (mode === 'reports' || mode === 'oversize' || mode === 'linked') {
    fs.mkdirSync(path.join(coverage,'flutter'));
    fs.writeFileSync(path.join(coverage,'flutter/raw.lcov.info'),`SF:${root.replace(/\\/g,'/')}/lib/main.dart\nDA:1,1\nend_of_record\nSF:C:/private/secret.dart\nDA:1,0\nend_of_record\n`);
    fs.writeFileSync(path.join(coverage,'flutter/summary.json'),'{}');
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
    if(mode==='reports') {
      const lcov=uploads.find(x=>x.name==='flutter-raw.lcov.info').data.toString();
      assert(lcov.includes('SF:lib/main.dart')); assert(!lcov.includes('private')); assert(!lcov.includes('DA:1,0'));
    }
  }
  console.log('PASS '+name);
}
(async()=>{
  for(const mode of ['partial','reports','missing','identity','oversize','linked','public','api','checksum'])
    await scenario(mode,mode,!['partial','reports'].includes(mode));
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
