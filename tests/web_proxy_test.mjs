import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {once} from 'node:events';
import {test} from 'node:test';
import {createWebServer} from '../scripts/serve-free.mjs';
import {validateTryonConfig, FIXED_MODEL} from '../scripts/tryon-proxy.mjs';

async function listen(server) {
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  return `http://127.0.0.1:${server.address().port}`;
}

test('网页固定模型代理：来源、请求覆盖、凭据隔离与错误处理', async t => {
  let calls = 0;
  let received;
  let mode = 'success';
  const privateValue = 'test-private-value';
  const upstream = createServer(async (req, res) => {
    calls++;
    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    received = {url: req.url, headers: req.headers, body: JSON.parse(Buffer.concat(chunks))};
    if (mode === 'redirect') {
      res.writeHead(307, {Location: '/redirect-target'}); res.end(); return;
    }
    res.setHeader('Content-Type', 'application/json');
    if (mode === 'error') {
      res.writeHead(429);
      res.end(JSON.stringify({code: 42901, message: privateValue, data: {error_code: 'RATE_LIMITED', api_key: privateValue}}));
    } else if (mode === 'invalid') {
      res.end('not-json');
    } else {
      res.end(JSON.stringify({code: 0, message: privateValue, data: {
        image: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB', mime: 'image/png',
        model: privateValue, api_key: privateValue, prompt: privateValue,
      }}));
    }
  });
  t.after(() => { upstream.closeAllConnections(); upstream.close(); });
  const backend = await listen(upstream);
  const config = validateTryonConfig({backendURL: `${backend}/tryon`, arkAPIKey: privateValue, accessToken: 'test-token'});
  const web = createWebServer({tryonConfig: config});
  t.after(() => { web.closeAllConnections(); web.close(); });
  const origin = await listen(web);
  const input = {
    person_image: 'person', garment_image: 'garment', size: '1024x1536', custom_prompt: '白色背景', lang: 'en',
    model: 'gemini', backendURL: 'https://untrusted.example/tryon',
    client_config: {provider: 'gemini', api_key: 'wrong-key'},
  };
  const post = (value = input, headers = {}, suffix = '') => fetch(`${origin}/api/tryon${suffix}`, {
    method: 'POST', headers: {'Content-Type': 'application/json', Origin: origin, ...headers},
    body: typeof value === 'string' ? value : JSON.stringify(value),
  });

  await t.test('请求固定模型并过滤上游回显，浏览器不接触 Key', async () => {
    const response = await post();
    assert.equal(response.status, 200);
    const result = await response.json();
    assert.equal(result.data.model, FIXED_MODEL.model);
    assert.deepEqual(Object.keys(result.data).sort(), ['image', 'mime', 'model']);
    assert.ok(!JSON.stringify(result).includes(privateValue));
    assert.equal(received.url, '/tryon');
    assert.equal(received.headers.authorization, 'Bearer test-token');
    assert.equal(received.body.model, 'browser-custom');
    assert.deepEqual(received.body.client_config, {...FIXED_MODEL, api_key: privateValue});
    assert.equal(received.body.custom_prompt, '白色背景');
    assert.equal(received.body.lang, 'en');
    assert.equal(received.body.backendURL, undefined);
    assert.equal(response.headers.get('cache-control'), 'no-store');
  });

  await t.test('拒绝跨站、缺失来源、URL 覆盖及错误方法', async () => {
    const before = calls;
    assert.equal((await post(input, {Origin: 'https://untrusted.example'})).status, 403);
    assert.equal((await post(input, {Origin: ''})).status, 403);
    assert.equal((await post(input, {}, '?tryon=https://untrusted.example')).status, 403);
    assert.equal((await fetch(`${origin}/api/tryon`)).status, 405);
    assert.equal(calls, before);
  });

  await t.test('私有配置、后端及 Git 文件不会作为静态资源公开', async () => {
    for (const path of ['/web.config.local.json', '/macos/Config.local.plist', '/.env', '/.git/config', '/scripts/tryon-proxy.mjs']) {
      assert.equal((await fetch(origin + path)).status, 404);
    }
    const response = await fetch(`${origin}/config.js`);
    assert.equal(response.status, 200);
    assert.ok(!(await response.text()).includes(privateValue));
  });

  await t.test('无效或过大请求在访问上游之前被拒绝', async () => {
    const before = calls;
    assert.equal((await post('{')).status, 400);
    assert.equal((await post({...input, size: 'invalid'})).status, 400);
    assert.equal((await post({...input, custom_prompt: 'x'.repeat(1001)})).status, 400);
    assert.equal((await post(input, {'Content-Type': 'text/plain'})).status, 415);
    assert.equal((await post({...input, person_image: 'x'.repeat(24 * 1024 * 1024)})).status, 413);
    assert.equal(calls, before);
  });

  await t.test('上游错误保留标准错误码并删除凭据', async () => {
    mode = 'error';
    const response = await post();
    assert.equal(response.status, 429);
    const result = await response.json();
    assert.equal(result.data.error_code, 'RATE_LIMITED');
    assert.ok(!JSON.stringify(result).includes(privateValue));
    mode = 'invalid';
    assert.equal((await post()).status, 502);
  });

  await t.test('禁止重定向转发图片和凭据', async () => {
    mode = 'redirect';
    const before = calls;
    assert.equal((await post()).status, 502);
    assert.equal(calls, before + 1);
  });

  await t.test('缺少配置时关闭生图，图库仍可用', async () => {
    const empty = createWebServer();
    t.after(() => { empty.closeAllConnections(); empty.close(); });
    const base = await listen(empty);
    assert.equal((await fetch(base)).status, 200);
    const response = await fetch(`${base}/api/tryon`, {
      method: 'POST', headers: {Origin: base, 'Content-Type': 'application/json'}, body: JSON.stringify(input),
    });
    assert.equal(response.status, 503);
  });

  await t.test('远程 HTTP 例外只接受显式本地配置，地址不能含重定向参数', () => {
    assert.throws(() => validateTryonConfig({backendURL: 'http://example.com/tryon', arkAPIKey: privateValue}));
    assert.doesNotThrow(() => validateTryonConfig({backendURL: 'http://example.com/tryon', allowHTTPForBackend: true, arkAPIKey: privateValue}));
    for (const backendURL of ['https://a:b@example.com', 'https://example.com?tryon=bad', 'https://example.com/#bad', 'https://example.com/other']) {
      assert.throws(() => validateTryonConfig({backendURL, arkAPIKey: privateValue}));
    }
    assert.throws(() => validateTryonConfig({backendURL: 'https://example.com', arkAPIKey: ''}));
  });
});
