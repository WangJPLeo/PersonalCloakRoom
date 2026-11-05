"""Publish a verified app, then remove earlier project-owned application bundles."""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile

BUNDLE_ID = 'app.personalcloakroom.capture'


def bundle_id(path):
    try:
        return plistlib.loads((path / 'Contents/Info.plist').read_bytes()).get('CFBundleIdentifier')
    except (OSError, ValueError):
        return None


def verify_signature(path):
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(path)], check=True)


def remove_older_bundles(root, keep, identities):
    removed = 0
    for parent, directories, _ in os.walk(root, followlinks=False):
        for name in list(directories):
            path = Path(parent) / name
            if path.is_symlink():
                directories.remove(name)
                continue
            if path.suffix != '.app':
                continue
            directories.remove(name)
            if path == keep or bundle_id(path) not in identities:
                continue
            shutil.rmtree(path)
            removed += 1
    return removed


def publish(staged, destination, backup_root, verify=verify_signature):
    if staged.is_symlink() or bundle_id(staged) != BUNDLE_ID:
        raise ValueError('待发布的应用包身份不匹配。')
    verify(staged)
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists() or destination.is_symlink():
        if destination.is_symlink() or bundle_id(destination) != BUNDLE_ID:
            raise ValueError('目标位置不是本项目的应用，已停止替换。')
    backup_root.mkdir(parents=True, exist_ok=True)
    backup_dir = Path(tempfile.mkdtemp(prefix='previous-app-', dir=backup_root))
    backup = backup_dir / destination.name
    if destination.exists():
        os.replace(destination, backup)
    try:
        os.replace(staged, destination)
    except BaseException:
        if backup.exists():
            os.replace(backup, destination)
        backup_dir.rmdir()
        raise
    # The verified new package is in place. Only now discard the previous one.
    shutil.rmtree(backup_dir)
    return remove_older_bundles(destination.parent, destination, {BUNDLE_ID})


if __name__ == '__main__':
    project = Path(__file__).resolve().parents[1]
    current = project / 'dist/衣橱快截.app'
    count = publish(Path(sys.argv[1]), current, project / '.build')
    # Diagnostic app bundles are generated test output, never distributable versions.
    count += remove_older_bundles(project / '.build', None, {
        'app.personalcloakroom.network-probe',
        'app.personalcloakroom.native-generation-test',
    })
    print(f'新版应用已验证发布；历史应用与诊断包清理完成（{count} 个）。')
