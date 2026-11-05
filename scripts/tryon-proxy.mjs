import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';

export const FIXED_MODEL = Object.freeze({
  provider: 'doubao',
  base_url: 'https://ark.cn-beijing.volces.com/api/v3',
  model: 'doubao-seedream-5-0-flash-260915',
});
const MAX_REQUEST_BYTES = 24 * 1024 * 1024;
const MAX_RESPONSE_BYTES = 42_000_000;
const ERROR_CODES = new Set([
  'AUTH_REQUIRED', 'AUTH_INVALID', 'ORIGIN_NOT_ALLOWED', 'REQUEST_TOO_LARGE',
  'INVALID_IMAGE_BASE64', 'UNSUPPORTED_IMAGE_TYPE', 'IMAGE_FILE_TOO_LARGE',
  'IMAGE_DIMENSIONS_INVALID', 'IMAGE_PIXEL_LIMIT_EXCEEDED', 'RATE_LIMITED',
  'DAILY_QUOTA_EXCEEDED', 'CONCURRENCY_LIMITED',
]);

export async function loadTryonConfig(root) {
  let data;
  try { data = await readFile(resolve(root, 'web.config.local.json'), 'utf8'); }
  catch (error) {
    if (error.code === 'ENOENT') return null;
    throw new Error('无法读取网页本地配置。');
  }
  try { return validateTryonConfig(JSON.parse(data)); }
  catch { throw new Error('网页本地配置无效，请检查配置文件。'); }
}

export function validateTryonConfig(value) {
  const url = new URL(value.backendURL);
  const local = ['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname);
  if (!['https:', 'http:'].includes(url.protocol) || url.username || url.password ||
      url.search || url.hash || !['', '/', '/tryon'].includes(url.pathname) ||
      (url.protocol === 'http:' && !local && value.allowHTTPForBackend !== true)) {
    throw new Error('换装服务地址无效。');
  }
  url.pathname = '/tryon';
  if (typeof value.arkAPIKey !== 'string' || !value.arkAPIKey.trim() || value.arkAPIKey.length > 4096 ||
      /[\r\n]/.test(value.arkAPIKey) ||
      (value.accessToken !== undefined && (typeof value.accessToken !== 'string' ||
        value.accessToken.length > 4096 || /[\r\n]/.test(value.accessToken)))) {
    throw new Error('服务凭据未配置或格式无效。');
  }
  return Object.freeze({endpoint: url.href, arkAPIKey: value.arkAPIKey.trim(), accessToken: value.accessToken || ''});
}

async function readRequest(req) {
  const chunks = [];
  let length = 0;
  // 超限时保持连接可写，以便向浏览器返回 413。
  for await (const chunk of req.iterator({destroyOnReturn: false})) {
    length += chunk.length;
    if (length > MAX_REQUEST_BYTES) {
      req.resume();
      throw Object.assign(new Error('请求过大'), {status: 413});
    }
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

export function createTryonProxy(config, {fetchImpl = fetch} = {}) {
  return async (req, res) => {
    const send = (status, body) => {
      res.writeHead(status, {'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store'});
      res.end(JSON.stringify(body));
    };
    const fail = (status, code = '') => send(status, {
      code: status, message: '换装服务请求失败，请稍后重试。', data: {error_code: code},
    });
    if (!config) { req.resume(); fail(503); return; }
    if (!/^application\/json(?:\s*;|$)/i.test(req.headers['content-type'] || '')) {
      req.resume(); fail(415); return;
    }
    if (Number(req.headers['content-length']) > MAX_REQUEST_BYTES) {
      req.resume(); fail(413, 'REQUEST_TOO_LARGE'); return;
    }
    let input;
    try {
      input = await readRequest(req);
      if (!input || typeof input !== 'object' ||
          typeof input.person_image !== 'string' || !input.person_image ||
          typeof input.garment_image !== 'string' || !input.garment_image ||
          !['1024x1536', '1024x1024', '1536x1024'].includes(input.size) ||
          (input.custom_prompt !== undefined && (typeof input.custom_prompt !== 'string' || input.custom_prompt.length > 1000))) {
        throw new Error('请求参数无效');
      }
    } catch (error) {
      fail(error.status || 400, error.status === 413 ? 'REQUEST_TOO_LARGE' : ''); return;
    }
    // 只转发图片和生成选项。URL、模型、Key 均由本机固定配置决定。
    const payload = {
      person_image: input.person_image, garment_image: input.garment_image,
      size: input.size, lang: input.lang === 'en' ? 'en' : 'zh', keep_face: true,
      custom_prompt: input.custom_prompt || '', model: 'browser-custom',
      client_config: {...FIXED_MODEL, api_key: config.arkAPIKey},
    };
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 300_000);
    const abort = () => { if (!res.writableEnded) controller.abort(); };
    res.on('close', abort);
    try {
      const headers = {'Content-Type': 'application/json', Accept: 'application/json'};
      if (config.accessToken) headers.Authorization = `Bearer ${config.accessToken}`;
      const upstream = await fetchImpl(config.endpoint, {
        method: 'POST', headers, body: JSON.stringify(payload), redirect: 'error', signal: controller.signal,
      });
      const chunks = [];
      let length = 0;
      for await (const chunk of upstream.body) {
        length += chunk.length;
        if (length > MAX_RESPONSE_BYTES) throw new Error('响应过大');
        chunks.push(chunk);
      }
      const result = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      if (!upstream.ok || result.code !== 0) {
        const code = result?.data?.error_code;
        fail([400, 401, 403, 413, 422, 429].includes(upstream.status) ? upstream.status : 502,
          ERROR_CODES.has(code) ? code : '');
        return;
      }
      const image = result.data?.image;
      const mime = result.data?.mime;
      if (typeof image !== 'string' || !image || !['image/png', 'image/jpeg', 'image/webp'].includes(mime)) {
        throw new Error('响应无效');
      }
      // 不透传上游消息、模型配置或其他可能回显凭据的字段。
      send(200, {code: 0, data: {image, mime, model: FIXED_MODEL.model}});
    } catch {
      if (!res.destroyed) fail(controller.signal.aborted ? 504 : 502);
    } finally {
      clearTimeout(timer);
      res.off('close', abort);
    }
  };
}
