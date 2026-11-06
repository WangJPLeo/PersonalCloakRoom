import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const html = fs.readFileSync(new URL('../index.html', import.meta.url), 'utf8');

const inlineScripts = [...html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/gi)];
assert.ok(inlineScripts.length > 0, 'no inline scripts found');
for (const [index, match] of inlineScripts.entries()) {
  new vm.Script(match[1], {filename: `index.html:inline-${index + 1}`});
}

// 改名升级必须保留同源旧设置，且不能覆盖新设置或在写入失败时删除旧值。
function runStorageUpgrade(entries, denyWrites = false) {
  const values = new Map(entries);
  const document = {documentElement: {dataset: {}}};
  const localStorage = {
    getItem: key => values.get(key) ?? null,
    setItem: (key, value) => {
      if (denyWrites) throw new Error('storage quota exceeded');
      values.set(key, value);
    },
    removeItem: key => values.delete(key),
  };
  vm.runInNewContext(inlineScripts[0][1], {document, localStorage});
  return {values, theme: document.documentElement.dataset.theme};
}

const migratedSettings = runStorageUpgrade([
  ['nvzhuang_theme', 'dark'],
  ['nvzhuang_compress_image', '0'],
  ['paipiange.tryon.settings.v1', '{"model":"legacy-model"}'],
]);
assert.equal(migratedSettings.theme, 'dark');
assert.equal(migratedSettings.values.get('PersonalCloakRoom.compressImage'), '0');
assert.equal(migratedSettings.values.get('PersonalCloakRoom.tryon.settings.v1'), '{"model":"legacy-model"}');
assert.equal(migratedSettings.values.has('paipiange.tryon.settings.v1'), false);
const newerSettings = runStorageUpgrade([
  ['nvzhuang_theme', 'dark'], ['PersonalCloakRoom.theme', 'light'],
]);
assert.equal(newerSettings.theme, 'light');
const quotaFailure = runStorageUpgrade([['nvzhuang_theme', 'dark']], true);
assert.equal(quotaFailure.values.get('nvzhuang_theme'), 'dark');
assert.equal(quotaFailure.values.has('PersonalCloakRoom.theme'), false);

const previousBrand = runStorageUpgrade([
  ['CinlyCloakRoom.theme', 'dark'],
  ['nvzhuang_theme', 'light'],
  ['CinlyCloakRoom.compressImage', '0'],
  ['CinlyCloakRoom.tryon.settings.v1', '{"model":"recent-model"}'],
  ['paipiange.tryon.settings.v1', '{"model":"older-model"}'],
]);
assert.equal(previousBrand.theme, 'dark');
assert.equal(previousBrand.values.get('PersonalCloakRoom.compressImage'), '0');
assert.equal(previousBrand.values.get('PersonalCloakRoom.tryon.settings.v1'), '{"model":"recent-model"}');
assert.equal(previousBrand.values.has('CinlyCloakRoom.tryon.settings.v1'), false);
assert.equal(previousBrand.values.has('paipiange.tryon.settings.v1'), false);
const previousBrandQuotaFailure = runStorageUpgrade([['CinlyCloakRoom.theme', 'dark']], true);
assert.equal(previousBrandQuotaFailure.values.get('CinlyCloakRoom.theme'), 'dark');

function extractFunction(name) {
  const patterns = [`function ${name}(`, `async function ${name}(`];
  const start = Math.min(...patterns.map(pattern => html.indexOf(pattern)).filter(index => index >= 0));
  assert.ok(Number.isFinite(start), `missing function ${name}`);
  const bodyStart = html.indexOf('{', start);
  let depth = 0;
  let quote = '';
  let escaped = false;
  for (let i = bodyStart; i < html.length; i++) {
    const char = html[i];
    if (quote) {
      if (escaped) escaped = false;
      else if (char === '\\') escaped = true;
      else if (char === quote) quote = '';
      continue;
    }
    if (char === "'" || char === '"' || char === '`') {
      quote = char;
      continue;
    }
    if (char === '{') depth++;
    if (char === '}') {
      depth--;
      if (depth === 0) return html.slice(start, i + 1);
    }
  }
  throw new Error(`unterminated function ${name}`);
}

const resolveEndpoint = vm.runInNewContext(`(${extractFunction('resolveTrustedTryonEndpoint')})`, {URL});
const siteOrigin = 'https://gallery.example';
const remoteOrigin = 'https://tryon.example';
const remoteSettings = {TRYON_ENDPOINT: remoteOrigin + '/tryon', TRUSTED_TRYON_ORIGINS: [remoteOrigin]};
assert.equal(resolveEndpoint({}, 'http://127.0.0.1:3000'), 'http://127.0.0.1:3000/api/tryon');
assert.equal(resolveEndpoint({}, siteOrigin), siteOrigin + '/api/tryon');
assert.equal(resolveEndpoint(remoteSettings, siteOrigin), remoteOrigin + '/tryon');
assert.equal(resolveEndpoint({...remoteSettings, TRYON_ENABLED: false}, siteOrigin), '');
assert.equal(resolveEndpoint({TRYON_ENDPOINT: remoteOrigin + '/tryon'}, siteOrigin), '');
for(const TRYON_ENDPOINT of [
  'http://tryon.example/tryon', 'https://untrusted.example/tryon',
  'https://user:password@tryon.example/tryon', remoteOrigin + '/tryon?redirect=other',
  remoteOrigin + '/tryon#private', remoteOrigin + '/other', '//untrusted.example/tryon',
  'javascript:alert(1)', 'https://tryon.example.untrusted.example/tryon',
]) assert.equal(resolveEndpoint({...remoteSettings, TRYON_ENDPOINT}, siteOrigin), '', 'reject an unsafe endpoint');
assert.equal(resolveEndpoint({...remoteSettings, TRYON_ENDPOINT: 'http://127.0.0.1:3000/api/tryon'}, siteOrigin), '');
assert.equal(resolveEndpoint({}, 'http://gallery.example'), '', 'remote HTTP must be rejected');

const helperNames = [
  'detectImageMimeFromBytes',
  'detectImageMimeFromBase64',
  'normalizeImageMime',
  'imageExtensionForMime',
  'resolveResultImageInfo',
  'createResultImageDataUrl',
  'parseTryonResponse',
  'getErrorMessageFromResponse',
];

const translations = {
  aiFailed: 'failed',
  aiGatewayErr: 'gateway',
  aiInvalidResponse: 'invalid response',
  aiHttpErr: 'http error',
  errAuthRequired: 'auth required',
  errAuthInvalid: 'auth invalid',
  errOriginNotAllowed: 'origin denied',
  errRequestTooLarge: 'too large',
  errInvalidImageBase64: 'invalid image',
  errUnsupportedImageType: 'unsupported image',
  errImageFileTooLarge: 'image too large',
  errImageDimensionsInvalid: 'bad dimensions',
  errImagePixelLimitExceeded: 'too many pixels',
  errRateLimited: 'rate limited',
  errDailyQuotaExceeded: 'quota exceeded',
  errConcurrencyLimited: 'concurrency limited',
};

const context = {
  atob,
  Uint8Array,
  t: key => translations[key] || key,
};
vm.createContext(context);
vm.runInContext(helperNames.map(extractFunction).join('\n'), context);

const png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB';
const jpeg = '/9j/4AAQSkZJRgABAQAAAQABAAD';
const webp = 'UklGRgQAAABXRUJQ';

assert.equal(context.detectImageMimeFromBase64(png), 'image/png');
assert.equal(context.detectImageMimeFromBase64(jpeg), 'image/jpeg');
assert.equal(context.detectImageMimeFromBase64(webp), 'image/webp');
assert.equal(context.imageExtensionForMime('image/jpeg'), 'jpg');
assert.equal(context.imageExtensionForMime('image/webp'), 'webp');

const resolved = context.resolveResultImageInfo(jpeg, 'image/png');
assert.equal(resolved.mime, 'image/jpeg', 'magic bytes must win over a mismatched declaration');
assert.equal(resolved.extension, 'jpg');
assert.match(context.createResultImageDataUrl(resolved), /^data:image\/jpeg;base64,/);

assert.throws(() => context.resolveResultImageInfo('cGxhaW4gdGV4dA==', ''), /unsupported/i);

function fakeResponse({status, contentType, jsonValue, jsonError}) {
  return {
    status,
    ok: status >= 200 && status < 300,
    headers: {get: name => name.toLowerCase() === 'content-type' ? contentType : null},
    json: async () => {
      if (jsonError) throw jsonError;
      return jsonValue;
    },
  };
}

assert.equal(await context.parseTryonResponse(fakeResponse({status: 502, contentType: 'text/html'})), null);
assert.equal(await context.parseTryonResponse(fakeResponse({status: 200, contentType: 'application/json', jsonError: new Error('bad json')})), null);
assert.deepEqual(
  await context.parseTryonResponse(fakeResponse({status: 400, contentType: 'application/problem+json', jsonValue: {message: 'bad'}})),
  {message: 'bad'},
);

assert.equal(context.getErrorMessageFromResponse({status: 413, ok: false}, null).code, 'REQUEST_TOO_LARGE');
assert.equal(context.getErrorMessageFromResponse({status: 401, ok: false}, null).code, 'AUTH_REQUIRED');
assert.equal(context.getErrorMessageFromResponse({status: 403, ok: false}, null).code, 'ORIGIN_NOT_ALLOWED');
assert.match(context.getErrorMessageFromResponse({status: 502, ok: false}, null).text, /502/);
assert.match(context.getErrorMessageFromResponse({status: 200, ok: true}, null).text, /invalid response/);

// 移动端以二进制保存新结果，同时兼容已有 Blob 记录与声明错误的图片类型。
const historyContext = vm.createContext({Blob, ArrayBuffer, Uint8Array, t:key=>key});
vm.runInContext([
  'detectImageMimeFromBytes', 'normalizeImageMime', 'normalizeResultImageBlob', 'historySaveErrorMessage',
].map(extractFunction).join('\n'), historyContext);
const pngBytes = Uint8Array.from(atob(png), char=>char.charCodeAt(0));
const oldBlob = new Blob([pngBytes], {type:'image/jpeg'});
for(const value of [oldBlob, pngBytes, pngBytes.buffer]) {
  const restored = await historyContext.normalizeResultImageBlob(value, 'image/jpeg');
  assert.equal(restored.type, 'image/png');
  assert.deepEqual(new Uint8Array(await restored.arrayBuffer()), pngBytes);
}
await assert.rejects(historyContext.normalizeResultImageBlob(new Uint8Array([1,2,3]).buffer), /unsupported/);
assert.equal(historyContext.historySaveErrorMessage({name:'QuotaExceededError'}), 'historySaveQuota');
assert.equal(historyContext.historySaveErrorMessage({name:'HistoryBlockedError'}), 'historySaveBlocked');
assert.equal(historyContext.historySaveErrorMessage({name:'SecurityError'}), 'historySaveUnavailable');

// 同步打开失败不能永久缓存失败状态；旧库迁移失败不能阻止保存新结果。
let openCalls = 0, closed = 0;
const db = {close:()=>{closed++;}};
const indexedDB = {open:()=>{
  if(++openCalls === 1) throw new DOMException('denied', 'SecurityError');
  const request = {result:db};
  queueMicrotask(()=>request.onsuccess());
  return request;
}};
const dbContext = vm.createContext({
  window:{indexedDB}, indexedDB, DOMException, setTimeout, clearTimeout,
  updateHistoryCount:async()=>{},
  migrateLegacyHistory:async()=>{throw new Error('legacy database unavailable');},
});
vm.runInContext(`let historyDbPromise = null;
  const HISTORY_DB_NAME = 'test-history', HISTORY_DB_VERSION = 2;
  const HISTORY_STORE = 'generations', HISTORY_META_STORE = 'metadata';
  ${extractFunction('openHistoryDB')}`, dbContext);
await assert.rejects(dbContext.openHistoryDB(), {name:'SecurityError'});
assert.equal(await dbContext.openHistoryDB(), db);
assert.equal(openCalls,2);
assert.equal(await dbContext.openHistoryDB(), db);
assert.equal(openCalls,2, 'successful connections are reused');
db.onversionchange();
assert.equal(closed,1, 'an old tab must release its connection for upgrades');
assert.equal(await dbContext.openHistoryDB(), db);
assert.equal(openCalls,3, 'invalidated connections must be reopened');
db.transaction = ()=>{throw new DOMException('connection lost', 'InvalidStateError');};
vm.runInContext(extractFunction('historyRequest'), dbContext);
await assert.rejects(dbContext.historyRequest('readwrite', ()=>{}), {name:'InvalidStateError'});
assert.equal(await dbContext.openHistoryDB(), db);
assert.equal(openCalls,4, 'a failed transaction must not retain a closed connection');

// 其他标签页占用旧库时，排队请求可能没有 blocked 事件；超时后仍可恢复，迟到连接必须关闭。
const queuedRequests = [], timers = [];
let lateConnectionsClosed = 0;
const queuedDB = {open:()=>{
  const request = {result:{close:()=>{lateConnectionsClosed++;}}};
  queuedRequests.push(request);
  return request;
}};
const queuedContext = vm.createContext({
  window:{indexedDB:queuedDB}, indexedDB:queuedDB, DOMException,
  setTimeout:callback=>{timers.push(callback); return timers.length;}, clearTimeout:()=>{},
  updateHistoryCount:async()=>{},
  migrateLegacyHistory:()=>new Promise(()=>{}),
});
vm.runInContext(`let historyDbPromise = null;
  const HISTORY_DB_NAME = 'queued-history', HISTORY_DB_VERSION = 2;
  const HISTORY_STORE = 'generations', HISTORY_META_STORE = 'metadata';
  ${extractFunction('openHistoryDB')}`, queuedContext);
const blockedOpen = queuedContext.openHistoryDB();
queuedRequests[0].onblocked();
await assert.rejects(blockedOpen, {name:'HistoryBlockedError'});
const queuedOpen = queuedContext.openHistoryDB();
timers[1]();
await assert.rejects(queuedOpen, {name:'HistoryBlockedError'});
const recoveredOpen = queuedContext.openHistoryDB();
queuedRequests[2].onsuccess();
assert.equal(await recoveredOpen, queuedRequests[2].result, 'a stalled migration must not block new records');
queuedRequests[0].onsuccess();
queuedRequests[1].onsuccess();
assert.equal(lateConnectionsClosed,2);
assert.equal(await queuedContext.openHistoryDB(), queuedRequests[2].result);

// 旧库读取尚未返回时清空历史，后台迁移不能把记录重新写回来。
let clearedDuringMigration = false, migrationWrites = 0;
const migrationContext = vm.createContext({
  readLegacyHistoryRecords:async()=>{
    clearedDuringMigration = true;
    return [{id:'old-record'}];
  },
});
vm.runInContext(`const HISTORY_STORE = 'generations', HISTORY_META_STORE = 'metadata';
  const LEGACY_HISTORY_DB_NAMES = ['legacy-history'];
  ${extractFunction('migrateLegacyHistory')}`, migrationContext);
await migrationContext.migrateLegacyHistory({transaction:(_, mode)=>{
  const tx = {objectStore:()=>({
    get:()=>{
      const request = {};
      queueMicrotask(()=>{
        request.result = clearedDuringMigration;
        request.onsuccess();
        if(mode === 'readwrite') queueMicrotask(()=>tx.oncomplete());
      });
      return request;
    },
    put:()=>{migrationWrites++;},
  })};
  return tx;
}});
assert.equal(migrationWrites,0, 'cleared records must not be restored by a delayed migration');

// 保存失败保留待保存结果；重试使用同一记录 ID，成功后才清除待保存状态。
let writes = 0;
const retriedRecords = [];
const notice = {hidden:true}, retry = {}, message = {};
const retryContext = vm.createContext({
  historySaveNotice:notice, historyRetry:retry, historySaveMessage:message,
  putHistoryRecord:async record=>{
    retriedRecords.push(record);
    if(++writes === 1) throw new DOMException('full', 'QuotaExceededError');
  },
  updateHistoryCount:async()=>{}, showHint:()=>{}, t:key=>key,
  historySaveErrorMessage:error=>error.name,
});
vm.runInContext(`let pendingHistoryRecord = {id:'same-result'};
  ${extractFunction('persistPendingHistory')}`, retryContext);
await retryContext.persistPendingHistory();
assert.equal(notice.hidden,false);
assert.equal(message.textContent,'QuotaExceededError');
assert.equal(retry.disabled,false);
await retryContext.persistPendingHistory();
assert.equal(notice.hidden,true);
assert.equal(retriedRecords[0],retriedRecords[1]);
await retryContext.persistPendingHistory();
assert.equal(writes,2, 'a saved result must not be written again');

console.log('frontend try-on tests passed');
