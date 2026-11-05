import {mkdir, readFile, writeFile, copyFile, lstat, realpath} from 'node:fs/promises';
import {resolve, join, sep} from 'node:path';
import {fileURLToPath} from 'node:url';
import vm from 'node:vm';

const root = fileURLToPath(new URL('../', import.meta.url));
const destination = join(root, 'dist', 'pages');

// 发布包只复制明确允许的文件，不递归复制仓库或本地配置。
export async function buildPages({source = root, output = destination} = {}) {
  const sourceRoot = await realpath(source);
  const catalog = await readFile(join(sourceRoot, 'data.js'), 'utf8');
  const {META, D} = vm.runInNewContext(catalog + ';({META,D})', {}, {timeout: 1000});
  if (!Array.isArray(D) || !D.length || META.total !== D.length) {
    throw new Error('图库数量与元数据不一致。');
  }
  const publicFiles = ['index.html', 'data.js'];
  const counts = {};
  const ids = new Set();
  for (const item of D) {
    if (!/^[A-Z]+-\d+$/.test(item.id) || ids.has(item.id)) throw new Error('服装编号无效或重复。');
    ids.add(item.id);
    counts[item.カテゴリ] = (counts[item.カテゴリ] || 0) + 1;
    for (const [key, directory] of [['サムネ', 'thumbs'], ['画像', 'img']]) {
      if (item[key] !== `${directory}/${item.id}.webp`) throw new Error('图库资源路径无效。');
      publicFiles.push('assets/' + item[key]);
    }
  }
  if (Object.keys(counts).length !== META.cats.length ||
      META.cats.some(category => counts[category] !== META.counts[category])) {
    throw new Error('图库分类数量与元数据不一致。');
  }
  // 在写入前验证所有路径；符号链接不能引入仓库外的私有文件。
  for (const file of publicFiles) {
    const path = join(sourceRoot, file);
    if (!(await lstat(path)).isFile() || !(await realpath(path)).startsWith(sourceRoot + sep)) {
      throw new Error('发布资源必须是项目内的普通文件。');
    }
  }
  await mkdir(output, {recursive: true});
  const {readdir} = await import('node:fs/promises');
  if ((await readdir(output)).length) throw new Error('发布目录必须为空，请先清理 dist/pages。');
  for (const file of publicFiles) {
    const target = join(output, file);
    await mkdir(resolve(target, '..'), {recursive: true});
    await copyFile(join(sourceRoot, file), target);
  }
  await writeFile(join(output, 'config.js'), `// GitHub Pages 仅提供图库，凭据不得写入前端文件。\nwindow.PCR_CONFIG = Object.freeze({\n  MODEL_NAME: 'doubao-seedream-5-0-flash-260915',\n  TRYON_ENABLED: false,\n});\n`);
  await writeFile(join(output, '.nojekyll'), '');
  return {items: D.length, files: publicFiles.length + 2};
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const result = await buildPages();
  console.log(`GitHub Pages 发布包已生成：${result.items} 套服装，${result.files} 个文件（dist/pages）。`);
}
