from pathlib import Path
import plistlib
import runpy
import tempfile
from unittest.mock import patch

module = runpy.run_path(str(Path(__file__).resolve().parents[1] / 'scripts/publish_app.py'))
publish = module['publish']
identity = module['BUNDLE_ID']


def app(path, name, bundle=identity):
    (path / 'Contents').mkdir(parents=True)
    (path / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': bundle}))
    (path / 'Contents/version').write_text(name)
    return path


with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    current = app(root / 'dist/衣橱快截.app', 'old')
    history = app(root / 'dist/archive/衣橱快截-old.app', 'older')
    other = app(root / 'dist/Other.app', 'unrelated', 'example.other')
    outside = app(root / 'unrelated/Copy.app', 'outside')
    link = root / 'dist/External.app'
    link.symlink_to(outside, target_is_directory=True)
    staged = app(root / 'stage/New.app', 'new')

    def rejected(_):
        raise ValueError('invalid signature')

    try:
        publish(staged, current, root / 'backups', verify=rejected)
        raise AssertionError('signature failure must abort publishing')
    except ValueError:
        pass
    assert (current / 'Contents/version').read_text() == 'old'
    assert history.exists()

    original_replace = module['os'].replace

    def fail_swap(source, destination):
        if source == staged:
            raise OSError('simulated publication failure')
        return original_replace(source, destination)

    with patch.object(module['os'], 'replace', side_effect=fail_swap):
        try:
            publish(staged, current, root / 'backups', verify=lambda _: None)
            raise AssertionError('replacement failure must be reported')
        except OSError:
            pass
    assert (current / 'Contents/version').read_text() == 'old'
    assert history.exists()

    count = publish(staged, current, root / 'backups', verify=lambda _: None)
    assert count == 1
    assert (current / 'Contents/version').read_text() == 'new'
    assert not history.exists()
    assert other.exists() and outside.exists() and link.is_symlink()
    assert not list((root / 'backups').iterdir())

print('通过打包替换、失败回滚、历史版本清理及其他应用保护检查。')
