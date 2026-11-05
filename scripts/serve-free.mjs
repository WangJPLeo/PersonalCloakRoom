import {createServer} from 'node:http';
import {createReadStream} from 'node:fs';
import {realpath, stat} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {resolve, sep} from 'node:path';
import {pipeline} from 'node:stream/promises';
import {createTryonProxy, loadTryonConfig} from './tryon-proxy.mjs';

const projectRoot = fileURLToPath(new URL('../', import.meta.url));
const mimeTypes = {'.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.webp': 'image/webp'};

export function createWebServer({root = projectRoot, tryonConfig = null} = {}) {
  const proxy = createTryonProxy(tryonConfig);
  return createServer(async (req, res) => {
    const port = req.socket.localPort;
    const allowedHosts = new Set([`127.0.0.1:${port}`, `localhost:${port}`]);
    const origin = `http://${req.headers.host}`;
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('Cross-Origin-Resource-Policy', 'same-origin');
    const finish = (status, message) => {
      res.writeHead(status, {'Content-Type': 'text/plain; charset=utf-8'});
      res.end(req.method === 'HEAD' ? undefined : message);
    };
    if (!allowedHosts.has(req.headers.host) ||
        (req.headers.origin && ![origin, `http://localhost:${port}`].includes(req.headers.origin))) {
      finish(403, 'Forbidden');
      return;
    }
    try {
      const url = new URL(req.url, origin);
      if (url.origin !== origin) {
        finish(403, 'Forbidden');
        return;
      }
      if (url.pathname === '/api/tryon') {
        if (req.method !== 'POST') {
          res.setHeader('Allow', 'POST');
          finish(405, 'Method Not Allowed');
          return;
        }
        if (url.search || req.headers.origin !== origin) {
          req.resume();
          finish(403, 'Forbidden');
          return;
        }
        await proxy(req, res);
        return;
      }
      if (!['GET', 'HEAD'].includes(req.method)) {
        res.setHeader('Allow', 'GET, HEAD');
        finish(405, 'Method Not Allowed');
        return;
      }
      const pathname = decodeURIComponent(url.pathname);
      const filename = pathname === '/' ? 'index.html' : pathname.slice(1);
      // 仅公开图库资源与不含凭据的前端配置文件。
      // Git 数据、.env 和后端源码不通过 HTTP 提供。
      if (!/^(?:index\.html|data\.js|config\.js|assets\/(?:img|thumbs)\/[A-Z]+-\d+\.webp)$/.test(filename)) {
        finish(404, 'Not Found');
        return;
      }
      const path = await realpath(resolve(root, filename));
      const realRoot = await realpath(root);
      if (!path.startsWith(realRoot + sep)) {
        finish(403, 'Forbidden');
        return;
      }
      const info = await stat(path);
      if (!info.isFile()) {
        finish(404, 'Not Found');
        return;
      }
      const ext = filename.slice(filename.lastIndexOf('.'));
      res.writeHead(200, {
        'Content-Type': mimeTypes[ext],
        'Content-Length': info.size,
        'Cache-Control': ext === '.webp' ? 'public, max-age=86400' : 'no-cache',
      });
      if (req.method === 'HEAD') res.end();
      else await pipeline(createReadStream(path), res);
    } catch (error) {
      if (res.headersSent) res.destroy();
      else finish(error instanceof URIError ? 400 : error.code === 'ENOENT' ? 404 : 500, 'Request failed');
    }
  });

}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const port = Number(process.env.PORT || 3000);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    console.error('PORT 必须是 1–65535 之间的整数。');
    process.exit(1);
  }
  try {
    const tryonConfig = await loadTryonConfig(projectRoot);
    const server = createWebServer({tryonConfig});
    server.on('error', error => {
      console.error(error.code === 'EADDRINUSE'
        ? `端口 ${port} 已被占用。可设置 PORT=3001 后重新启动。`
        : `启动失败：${error.code || 'UNKNOWN'}`);
      process.exitCode = 1;
    });
    server.listen(port, '127.0.0.1', () => {
      console.log(`PersonalCloakRoom 已启动：http://127.0.0.1:${port}`);
      console.log(tryonConfig ? 'AI 换装已使用固定模型配置。按 Ctrl+C 停止服务。'
        : '免费图库可用；AI 换装需先填写 web.config.local.json。');
    });
  } catch {
    console.error('网页本地配置无效，请检查 web.config.local.json。');
    process.exitCode = 1;
  }
}
