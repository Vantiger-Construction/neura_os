"""Prepare genuine Unity references and compile every tracked Neura C# file.

This is a source-analysis harness, not a Unity editor/player build or test run.
No editor activation, native API calls, generated API stubs or source exclusions.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tarfile
import urllib.request
import xml.etree.ElementTree as ET

VERSION = '6000.6.6f1'
URL = 'https://download.unity3d.com/download_unity/d20c9ac777da/LinuxEditorInstaller/Unity-6000.6.6f1.tar.xz'
SHA256 = '64ea1568976f4e470a9da4db2576116807798c710523f4d0fe13e27fb8635a44'
REPO = Path(__file__).resolve().parents[2]


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def extract_sdk(archive, destination):
    if digest(archive) != SHA256:
        raise ValueError('Unity archive SHA-256 mismatch')
    with tarfile.open(archive, 'r|xz') as stream:
        for member in stream:
            path = Path(member.name)
            managed = member.name.startswith('Editor/Data/Managed/') and path.suffix == '.dll'
            package = any(member.name.startswith('Editor/Data/Resources/PackageManager/BuiltInPackages/' + name + '/')
                          for name in ('com.unity.test-framework', 'com.unity.ext.nunit'))
            if not member.isfile() or not (managed or package):
                continue
            if path.is_absolute() or '..' in path.parts:
                raise ValueError('Unsafe Unity archive path')
            target = destination / path
            target.parent.mkdir(parents=True, exist_ok=True)
            with stream.extractfile(member) as source, target.open('wb') as output:
                import shutil
                shutil.copyfileobj(source, output)


def write_project(path, assembly, sources, references):
    root = ET.Element('Project', Sdk='Microsoft.NET.Sdk')
    props = ET.SubElement(root, 'PropertyGroup')
    values = {'TargetFramework': 'net8.0', 'AssemblyName': assembly,
              'EnableDefaultCompileItems': 'false', 'GenerateAssemblyInfo': 'false',
              'AllowUnsafeBlocks': 'true', 'EnableNETAnalyzers': 'false',
              'DefineConstants': 'UNITY_EDITOR;UNITY_6000_0_OR_NEWER;UNITY_2023_2_OR_NEWER'}
    for key, value in values.items():
        ET.SubElement(props, key).text = value
    items = ET.SubElement(root, 'ItemGroup')
    for reference in references:
        entry = ET.SubElement(items, 'Reference', Include=reference.stem)
        ET.SubElement(entry, 'HintPath').text = str(reference)
    for source in sources:
        ET.SubElement(items, 'Compile', Include=str(source))
    ET.indent(root)
    path.parent.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(root).write(path, encoding='unicode')


def prepare(output, sdk):
    version_file = REPO / 'prototypes/unity-presence/ProjectSettings/ProjectVersion.txt'
    if version_file.read_text().strip() != 'm_EditorVersion: ' + VERSION:
        raise ValueError('Reviewed Unity editor version changed')
    data = sdk / 'Editor/Data'
    packages = data / 'Resources/PackageManager/BuiltInPackages'
    framework = packages / 'com.unity.test-framework'
    nunit = packages / 'com.unity.ext.nunit'
    manifest = json.loads((REPO / 'prototypes/unity-presence/Packages/manifest.json').read_text())
    for directory, expected in ((framework, '1.8.0'), (nunit, '2.1.0')):
        if json.loads((directory / 'package.json').read_text())['version'] != expected:
            raise ValueError('Unexpected bundled Unity package version')
    if manifest['dependencies']['com.unity.test-framework'] != '1.8.0':
        raise ValueError('Prototype test framework must match the reviewed editor bundle')
    managed = data / 'Managed'
    references = sorted(managed.glob('*.dll')) + sorted((managed / 'UnityEngine').glob('*.dll'))
    references = [p for p in references if not p.name.startswith(('System.', 'Microsoft.', 'netstandard', 'mscorlib'))]
    references += sorted(nunit.rglob('nunit.framework.dll'))
    required = {'UnityEngine.CoreModule.dll', 'UnityEditor.CoreModule.dll', 'nunit.framework.dll'}
    if not required.issubset({p.name for p in references}):
        raise ValueError('Genuine Unity/NUnit references missing')
    dependency = output / 'framework/framework.csproj'
    runtime_sources = sorted((framework / 'UnityEngine.TestRunner').rglob('*.cs'))
    if not runtime_sources:
        raise ValueError('Unmodified Unity test-framework source is missing')
    write_project(dependency, 'UnityEngine.TestRunner', runtime_sources, references)
    dependency_dll = dependency.parent / 'bin/Debug/net8.0/UnityEngine.TestRunner.dll'
    tracked = subprocess.check_output(['git', 'ls-files', '-z', '--', '*.cs'], cwd=REPO).decode().split('\0')
    sources = [REPO / p for p in tracked if p]
    if not sources:
        raise ValueError('No tracked C# sources')
    project = output / 'authored/neura.csproj'
    write_project(project, 'Neura.SecurityCompilation', sources, references + [dependency_dll])
    receipt = {'editor': VERSION, 'archive_url': URL, 'archive_sha256': SHA256,
               'framework': '1.8.0', 'nunit': '2.1.0',
               'tracked_sources': {str(p.relative_to(REPO)): digest(p) for p in sources},
               'references': {str(p.relative_to(sdk)): digest(p) for p in references},
               'scope': 'Compile/source analysis only; no Unity editor, play-mode or device acceptance'}
    (output / 'csharp-source-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(f'Prepared all {len(sources)} tracked C# sources with genuine Unity references', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--sdk-root', type=Path, help='Already extracted official SDK (local verification only)')
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    sdk = args.sdk_root.resolve() if args.sdk_root else output / 'sdk'
    if not args.sdk_root:
        archive = output / 'unity.tar.xz'
        with urllib.request.urlopen(URL, timeout=120) as source, archive.open('wb') as destination:
            import shutil
            shutil.copyfileobj(source, destination)
        extract_sdk(archive, sdk)
        archive.unlink()
    prepare(output, sdk)


if __name__ == '__main__':
    main()
