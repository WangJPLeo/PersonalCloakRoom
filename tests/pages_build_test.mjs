import assert from 'node:assert/strict';
import {mkdtemp, mkdir, writeFile, readFile, readdir, rm, symlink} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {test} from 'node:test';
import vm from 'node:vm';
import {buildPages} from '../scripts/build-pages.mjs';

async function fixture(t, mutate = item => item) {
  const dir = await mkdtemp(join(tmpdir(), 'pcr-pages-test-'));
  t.after(() => rm(dir, {recursive: true, force: true}));
  const source = join(dir, 'source'), output = join(dir, 'output');
  await mkdir(join(source, 'assets', 'img'), {recursive: true});
  await mkdir(join(source, 'assets', 'thumbs'), {recursive: true});
  await writeFile(join(source, 'index.html'), '<html><script src="config.js"></script></html>');
  const item = mutate({id: 'QIP-0001', カテゴリ: '中式', サムネ: 'thumbs/QIP-0001.webp', 画像: 'img/QIP-0001.webp'});
  await writeFile(join(source, 'data.js'), `const META={total:1,cats:['中式'],counts:{'中式':1}}; const D=${JSON.stringify([item])};`);
  await writeFile(join(source, 'assets/img/QIP-0001.webp'), 'image');
  await writeFile(join(source, 'assets/thumbs/QIP-0001.webp'), 'thumbnail');
  return {dir, source, output};
}

test('发布只包含允许的公开文件，并在静态站禁用 AI 上传', async t => {
  const {source, output} = await fixture(t);
  for (const filename of ['.env', 'web.config.local.json', 'config.js', 'photo.jpg']) {
    await writeFile(join(source, filename), 'private-test-value');
  }
  await buildPages({source, output});
  assert.deepEqual((await readdir(output)).sort(), ['.nojekyll', 'assets', 'config.js', 'data.js', 'index.html']);
  const config = await readFile(join(output, 'config.js'), 'utf8');
  assert.ok(!config.includes('private-test-value'));
  const context = {window: {}};
  vm.runInNewContext(config, context);
  assert.equal(context.window.PCR_CONFIG.TRYON_ENABLED, false);
  assert.equal(await readFile(join(output, 'assets/img/QIP-0001.webp'), 'utf8'), 'image');
  // 拒绝重复使用残留目录，避免旧文件随新版本发布。
  await assert.rejects(buildPages({source, output}), /发布目录必须为空/);
});

test('缺少图库图片时拒绝发布', async t => {
  const options = await fixture(t);
  await rm(join(options.source, 'assets/img/QIP-0001.webp'));
  await assert.rejects(buildPages(options), {code: 'ENOENT'});
});

test('拒绝通过数据路径访问私有文件', async t => {
  const options = await fixture(t, item => ({...item, 画像: '../../web.config.local.json'}));
  await assert.rejects(buildPages(options), /路径无效/);
});

test('拒绝通过图片符号链接发布私有文件', async t => {
  const options = await fixture(t);
  const image = join(options.source, 'assets/img/QIP-0001.webp');
  await writeFile(join(options.dir, 'private.json'), 'private-test-value');
  await rm(image);
  await symlink(join(options.dir, 'private.json'), image);
  await assert.rejects(buildPages(options), /普通文件/);
});

test('拒绝通过图片目录符号链接发布外部文件', async t => {
  const options = await fixture(t);
  await mkdir(join(options.dir, 'private'));
  await writeFile(join(options.dir, 'private/QIP-0001.webp'), 'private-test-value');
  await rm(join(options.source, 'assets/img'), {recursive: true});
  await symlink(join(options.dir, 'private'), join(options.source, 'assets/img'));
  await assert.rejects(buildPages(options), /普通文件/);
});
