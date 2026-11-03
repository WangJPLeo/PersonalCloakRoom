import {createServer} from 'node:http';
import {createReadStream} from 'node:fs';
import {realpath, stat} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {resolve, sep} from 'node:path';
import {pipeline} from 'node:stream/promises';

const root = fileURLToPath(new URL('../', import.meta.url));
const port = Number(process.env.PORT || 3000);
if (!Number.isInteger(port) || port < 1 || port > 65535) {
  console.error('PORT 必须是 1–65535 之间的整数。');
  process.exit(1);
}
const origin = `http://127.0.0.1:${port}`;
const allowedHosts = new Set([`127.0.0.1:${port}`, `localhost:${port}`]);
const mimeTypes = {'.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.webp': 'image/webp'};

const server = createServer(async (req, res) => {
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
  if (!['GET', 'HEAD'].includes(req.method)) {
    res.setHeader('Allow', 'GET, HEAD');
    finish(405, 'Method Not Allowed');
    return;
  }
  try {
    const url = new URL(req.url, origin);
    if (url.origin !== origin) {
      finish(403, 'Forbidden');
      return;
    }
    const pathname = decodeURIComponent(url.pathname);
    const filename = pathname === '/' ? 'index.html' : pathname.slice(1);
    // 仅公开图库资源，配置文件、Git 数据和后端源码不通过 HTTP 提供。
    if (!/^(?:index\.html|data\.js|assets\/(?:img|thumbs)\/[A-Z]+-\d+\.webp)$/.test(filename)) {
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

server.on('error', error => {
  console.error(error.code === 'EADDRINUSE'
    ? `端口 ${port} 已被占用。可设置 PORT=3001 后重新启动。`
    : `启动失败：${error.code || 'UNKNOWN'}`);
  process.exitCode = 1;
});
server.listen(port, '127.0.0.1', () => {
  console.log(`免费图库已启动：${origin}`);
  console.log('无需 API Key。按 Ctrl+C 停止服务。');
  console.log('AI 换装生成属于可选扩展，需要另行配置后端。');
});
