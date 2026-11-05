import json
from pathlib import Path
import runpy
import tempfile

package = runpy.run_path(str(Path(__file__).resolve().parents[1] / 'scripts/package_gallery.py'))['package_gallery']
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    assets = root / 'assets'
    for folder in ['img', 'thumbs']:
        (assets / folder).mkdir(parents=True)
        (assets / folder / 'TEST-1.webp').write_bytes(b'image fixture')
    entry = {'id': 'TEST-1', 'カテゴリ': 'パーティ', 'キーワード': 'blue dress',
             '画像': 'img/TEST-1.webp', 'サムネ': 'thumbs/TEST-1.webp'}
    source = root / 'data.js'

    def write(items):
        source.write_text('const META={};\nconst D=' + json.dumps(items) + ';\nthrow new Error("must never execute");')

    write([entry])
    target = root / 'Gallery'
    assert package(source, assets, target) == 1
    record = json.loads((target / 'catalog.json').read_text())[0]
    assert record['category'] == '派对'
    assert (target / record['image']).read_bytes() == b'image fixture'
    for items in [[entry, entry], [dict(entry, 画像='../private.webp')], [dict(entry, 画像='https://example.com/private.webp')]]:
        write(items)
        try:
            package(source, assets, root / 'Rejected')
            raise AssertionError('unsafe catalog must be rejected')
        except ValueError:
            pass
    write([entry])
    (assets / 'img/TEST-1.webp').unlink()
    external = root / 'private.webp'
    external.write_bytes(b'private fixture')
    (assets / 'img/TEST-1.webp').symlink_to(external)
    try:
        package(source, assets, root / 'RejectedLink')
        raise AssertionError('external symlink must be rejected')
    except ValueError:
        pass
print('通过图库打包、分类转换、路径与软链接安全检查。')
