#!/usr/bin/env python3
"""Compile the actual Android PackageImporter and verify two OTA ZIPs A/B/A.

This is an offline JVM audit. It never changes the Android project, downloads
dependencies, installs a wallpaper, or claims vehicle runtime behavior.

Example:
    python3 scripts/verify_studio_import.py \
      --android-project /path/to/cadillac-wallpaper-studio-android \
      --a /path/to/A.zip --b /path/to/B.zip \
      --work build/studio-import-audit
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


AUDIT_SOURCE = Path(__file__).resolve().with_name('StudioImportAudit.kt')
IMPORTER_FILES = ('PackageImporter.kt', 'ThemePackage.kt')


class AuditError(RuntimeError):
    pass


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1 << 20), b''):
            digest.update(block)
    return digest.hexdigest()


def required_sources(project: Path) -> list[Path]:
    source_dir = project / 'app/src/main/java/com/cadillac/wallpaperstudio'
    sources = [source_dir / name for name in IMPORTER_FILES]
    missing = [str(path) for path in [*sources, AUDIT_SOURCE] if not path.is_file()]
    if missing:
        raise AuditError('Actual Android importer source is unavailable: ' + ', '.join(missing))
    return [*sources, AUDIT_SOURCE]


def declared_version(path: Path, pattern: str, label: str) -> str:
    if not path.is_file():
        raise AuditError(f'Cannot discover {label}: missing {path}; pass its version explicitly')
    matches = re.findall(pattern, path.read_text(encoding='utf-8'))
    if len(set(matches)) != 1:
        raise AuditError(f'Cannot uniquely discover {label} from {path}; pass its version explicitly')
    return matches[0]


def cached_artifact(cache: Path, group: str, name: str, version: str) -> Path:
    root = cache / group / name / version
    matches = list(root.glob(f'*/{name}-{version}.jar'))
    if len(matches) != 1:
        raise AuditError(f'Missing or ambiguous cached {group}:{name}:{version} under {root}')
    return matches[0]


def cached_optional_version(cache: Path, group: str, name: str, preferred: str) -> str:
    root = cache / group / name
    versions = [path.name for path in root.iterdir() if path.is_dir()] if root.is_dir() else []
    if preferred in versions:
        return preferred
    if len(versions) == 1:
        return versions[0]
    raise AuditError(
        f'Cannot uniquely discover cached {group}:{name} (found {versions}); '
        f'pass its version explicitly'
    )


def java_executable(explicit: Path | None) -> Path:
    candidates = []
    if explicit:
        candidates.append(explicit)
    elif os.environ.get('JAVA_HOME'):
        candidates.append(Path(os.environ['JAVA_HOME']) / 'bin/java')
    else:
        found = shutil.which('java')
        if found:
            candidates.append(Path(found))
    if not candidates or not candidates[0].is_file():
        raise AuditError('Java executable unavailable; pass --java or set JAVA_HOME')
    return candidates[0]


def run_audit(args: argparse.Namespace) -> Path:
    project = args.android_project.resolve()
    a, b = args.a.resolve(), args.b.resolve()
    if not a.is_file() or not b.is_file():
        raise AuditError('Both --a and --b must name existing OTA ZIP files')
    if a == b or sha256(a) == sha256(b):
        raise AuditError('A and B must be distinct OTA ZIP contents')
    sources = required_sources(project)
    source_hashes = {source.name: sha256(source) for source in sources}
    kotlin_version = args.kotlin_version or declared_version(
        project / 'build.gradle.kts',
        r'id\("org\.jetbrains\.kotlin\.android"\)\s+version\s+"([^"]+)"',
        'Kotlin compiler version',
    )
    json_version = args.json_version or declared_version(
        project / 'app/build.gradle.kts',
        r'testImplementation\("org\.json:json:([^"]+)"\)',
        'org.json version',
    )
    gradle_home = (args.gradle_user_home or Path(os.environ.get('GRADLE_USER_HOME', Path.home() / '.gradle'))).resolve()
    cache = gradle_home / 'caches/modules-2/files-2.1'
    if not cache.is_dir():
        raise AuditError(f'Gradle artifact cache is unavailable: {cache}')
    annotations_version = args.annotations_version or cached_optional_version(
        cache, 'org.jetbrains', 'annotations', '13.0')
    coroutines_version = args.coroutines_version or cached_optional_version(
        cache, 'org.jetbrains.kotlinx', 'kotlinx-coroutines-core-jvm', '1.8.0')
    jars = {
        'compiler': cached_artifact(cache, 'org.jetbrains.kotlin', 'kotlin-compiler-embeddable', kotlin_version),
        'stdlib': cached_artifact(cache, 'org.jetbrains.kotlin', 'kotlin-stdlib', kotlin_version),
        'annotations': cached_artifact(cache, 'org.jetbrains', 'annotations', annotations_version),
        'coroutines': cached_artifact(cache, 'org.jetbrains.kotlinx', 'kotlinx-coroutines-core-jvm', coroutines_version),
        'json': cached_artifact(cache, 'org.json', 'json', json_version),
    }
    java = java_executable(args.java)
    version_run = subprocess.run([str(java), '-version'], capture_output=True, text=True, check=False)
    if version_run.returncode:
        raise AuditError(f'Java executable failed: {java}')
    args.work.mkdir(parents=True, exist_ok=True)
    run_dir = Path(tempfile.mkdtemp(prefix='import-audit-', dir=args.work)).resolve()
    classes = run_dir / 'classes'
    classes.mkdir()
    compiler_cp = os.pathsep.join(str(jars[key]) for key in ('compiler', 'stdlib', 'annotations', 'coroutines'))
    runtime_cp = os.pathsep.join(str(jars[key]) for key in ('stdlib', 'annotations', 'json'))
    compile_command = [str(java), '-cp', compiler_cp, 'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler',
                       '-no-stdlib', '-no-reflect', '-jvm-target', '17', '-classpath', runtime_cp,
                       '-d', str(classes), *(str(source) for source in sources)]
    subprocess.run(compile_command, check=True)
    report_path = run_dir / 'actual-importer-report.json'
    subprocess.run([str(java), '-Djava.awt.headless=true', '-cp',
                    str(classes) + os.pathsep + runtime_cp,
                    'com.cadillac.wallpaperstudio.StudioImportAudit',
                    str(report_path), str(run_dir / 'library'), str(a), str(b)], check=True)
    if not report_path.is_file():
        raise AuditError('Importer audit completed without its report')
    if any(sha256(source) != source_hashes[source.name] for source in sources):
        raise AuditError('An importer or audit source changed during verification')
    report = json.loads(report_path.read_text(encoding='utf-8'))
    if not report.get('passed') or not report.get('aBAReimportStable'):
        raise AuditError('Importer audit did not report a passing A/B/A result')
    report['sourceSha256'] = source_hashes
    report['dependencyVersions'] = {
        'kotlin': kotlin_version, 'annotations': annotations_version,
        'coroutines': coroutines_version, 'orgJson': json_version,
        'java': version_run.stderr.splitlines()[0] if version_run.stderr else version_run.stdout.splitlines()[0],
    }
    report['artifactSha256'] = {key: sha256(path) for key, path in jars.items()}
    report['sourceProjectName'] = project.name
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return report_path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--android-project', type=Path, required=True,
                        help='Local Android Studio project containing the actual PackageImporter.kt')
    parser.add_argument('--a', type=Path, required=True, help='First OTA ZIP')
    parser.add_argument('--b', type=Path, required=True, help='Second, different OTA ZIP')
    parser.add_argument('--work', type=Path, required=True, help='Directory for isolated audit output')
    parser.add_argument('--java', type=Path, help='JDK 17+ java executable (else JAVA_HOME/PATH)')
    parser.add_argument('--gradle-user-home', type=Path, help='Gradle user home (else GRADLE_USER_HOME/~/.gradle)')
    parser.add_argument('--kotlin-version', help='Override Kotlin compiler version discovered from Android project')
    parser.add_argument('--json-version', help='Override org.json version discovered from Android project')
    parser.add_argument('--annotations-version', help='Override cached JetBrains annotations version')
    parser.add_argument('--coroutines-version', help='Override cached coroutines JVM version')
    args = parser.parse_args()
    try:
        report = run_audit(args)
    except (AuditError, subprocess.CalledProcessError, OSError, ValueError) as error:
        print(f'Importer audit failed: {error}', file=sys.stderr)
        return 1
    print(f'Actual PackageImporter A/B/A passed; report: {report}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
