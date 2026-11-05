"""Package only catalogued garment assets; parse data.js as data, never execute it."""
import json
from pathlib import Path
import re
import shutil
import sys


def read_items(source):
    text = source.read_text(encoding='utf-8')
    match = re.search(r'(?:^|\n)\s*const\s+D\s*=\s*', text)
    if not match:
        raise ValueError('没有找到服装图库数据。')
    records, _ = json.JSONDecoder().raw_decode(text[match.end():])
    if not isinstance(records, list) or not 0 < len(records) <= 10000:
        raise ValueError('图库记录数量无效。')
    return records


def source_image(assets, relative, folder, identifier):
    if not isinstance(relative, str) or not re.fullmatch(
        re.escape(folder) + '/' + re.escape(identifier) + r'\.(?:webp|png|jpg|jpeg)', relative
    ):
        raise ValueError('图库图片路径格式无效。')
    path = assets / relative
    if path.is_symlink() or not path.resolve().is_relative_to(assets.resolve()) or not path.is_file():
        raise ValueError('图库图片缺失或路径不安全。')
    return path


def package_gallery(source, assets, destination):
    records = read_items(source)
    categories = {'パーティ': '派对', '水着': '泳装'}
    validated = []
    seen = set()
    for item in records:
        identifier = item.get('id', '')
        if not isinstance(identifier, str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,64}', identifier) or identifier in seen:
            raise ValueError('图库编号无效或重复。')
        seen.add(identifier)
        category, keywords = item.get('カテゴリ'), item.get('キーワード', '')
        if not isinstance(category, str) or not 0 < len(category) <= 30 or not isinstance(keywords, str) or len(keywords) > 2000:
            raise ValueError('图库分类或关键词格式无效。')
        original = source_image(assets, item.get('画像'), 'img', identifier)
        thumbnail = source_image(assets, item.get('サムネ'), 'thumbs', identifier)
        validated.append((identifier, categories.get(category, category), keywords, original, thumbnail))

    (destination / 'images').mkdir(parents=True, exist_ok=True)
    (destination / 'thumbs').mkdir(exist_ok=True)
    output = []
    for identifier, category, keywords, original, thumbnail in validated:
        image_path, thumb_path = 'images/' + original.name, 'thumbs/' + thumbnail.name
        shutil.copy2(original, destination / image_path)
        shutil.copy2(thumbnail, destination / thumb_path)
        output.append({'id': identifier, 'category': category, 'keywords': keywords,
                       'image': image_path, 'thumbnail': thumb_path})
    (destination / 'catalog.json').write_text(json.dumps(output, ensure_ascii=False), encoding='utf-8')
    return len(output)


if __name__ == '__main__':
    project = Path(__file__).resolve().parents[2]
    count = package_gallery(project / 'data.js', project / 'assets', Path(sys.argv[1]))
    print(f'已打包 {count} 套离线服装及缩略图。')
