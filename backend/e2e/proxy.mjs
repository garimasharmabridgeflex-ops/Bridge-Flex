// Local admin-console server for E2E checks.
//
// Serves backend/public/admin exactly like Firebase Hosting would in
// production, but:
//   * /<EndpointName> is proxied to the matching local functions-core
//     process instead of a Cloud Functions rewrite (ports parsed from
//     ../services/core/run-local.sh, so the two can never drift),
//   * the page's FIREBASE_CONFIG is pointed at demo-bridgeflex and both
//     Firebase SDKs are wired to the local emulators (the console ships
//     with production config baked in and has no emulator story of its own).
//
// Usage: node proxy.mjs   (env: PORT, default 5050)
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const publicDir = path.resolve(here, '../public');
const runLocal = fs.readFileSync(path.resolve(here, '../services/core/run-local.sh'), 'utf8');

// [FunctionName]=8215  →  { FunctionName: 8215 }
const ports = {};
for (const [, name, port] of runLocal.matchAll(/\[([A-Za-z0-9]+)\]=(\d+)/g)) {
  ports[name] = Number(port);
}

const AUTH_EMU = 'http://127.0.0.1:9099';
const FS_EMU_HOST = '127.0.0.1';
const FS_EMU_PORT = 8180;

function transformAdminHtml(html) {
  let out = html.replace(
    /projectId: "kvision-503115"/,
    'projectId: "demo-bridgeflex"'
  ).replace(
    /authDomain: "kvision-503115\.firebaseapp\.com"/,
    'authDomain: "demo-bridgeflex.firebaseapp.com"'
  );
  const anchor = 'try { firebase.initializeApp(FIREBASE_CONFIG); } catch (e) { console.warn(\'Firebase init\', e); }';
  const inject = `
${anchor}
// [e2e proxy] Point both SDKs at the local emulators before anything signs in
// or opens a listener — the shipped console only knows production.
try { firebase.auth().useEmulator('${AUTH_EMU}'); } catch (e) { console.warn('auth emulator', e); }
try { firebase.firestore().useEmulator('${FS_EMU_HOST}', ${FS_EMU_PORT}); } catch (e) { console.warn('firestore emulator', e); }`;
  if (!out.includes(anchor)) {
    console.warn('proxy: initializeApp anchor not found — emulator wiring NOT injected');
  }
  out = out.replace(anchor, inject);
  return out;
}

const mime = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript',
  '.css': 'text/css',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.json': 'application/json',
};

function serveStatic(req, res, urlPath) {
  let rel = urlPath === '/' ? '/admin' : urlPath;
  if (rel === '/admin' || rel.startsWith('/admin/')) rel = '/admin/index.html';
  const file = path.normalize(path.join(publicDir, rel));
  if (!file.startsWith(publicDir)) {
    res.writeHead(403).end('forbidden');
    return;
  }
  fs.readFile(file, (err, buf) => {
    if (err) {
      res.writeHead(404, { 'content-type': 'text/plain' }).end('not found: ' + rel);
      return;
    }
    let body = buf;
    if (file.endsWith('index.html')) body = transformAdminHtml(buf.toString('utf8'));
    res.writeHead(200, { 'content-type': mime[path.extname(file)] || 'application/octet-stream' });
    res.end(body);
  });
}

const server = http.createServer(async (req, res) => {
  const urlPath = decodeURIComponent(new URL(req.url, 'http://x').pathname);

  // Endpoint proxy: /GetFeatureFlags → 127.0.0.1:8215 etc.
  const name = urlPath.replace(/^\//, '');
  if (ports[name]) {
    const chunks = [];
    for await (const c of req) chunks.push(c);
    const body = chunks.length ? Buffer.concat(chunks) : undefined;
    try {
      const upstream = await fetch(`http://127.0.0.1:${ports[name]}/`, {
        method: req.method,
        headers: {
          'content-type': req.headers['content-type'] || 'application/json',
          authorization: req.headers.authorization || '',
        },
        body,
      });
      const text = await upstream.text();
      res.writeHead(upstream.status, { 'content-type': upstream.headers['content-type'] || 'application/json' });
      res.end(text);
    } catch (err) {
      res.writeHead(502, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ error: { code: 'PROXY_DOWN', message: `${name} local process not running: ${err.message}` } }));
    }
    return;
  }

  serveStatic(req, res, urlPath);
});

const port = Number(process.env.PORT || 5050);
server.listen(port, '127.0.0.1', () => {
  console.log(`admin console: http://127.0.0.1:${port}/admin  (${Object.keys(ports).length} endpoint ports known)`);
});
