// morseboy1 — tiny zero-dependency dev server for the mGBA WASM emulator.
//
// Serves web/index.html, the mgba-wasm runtime (js + wasm), and the freshly
// built ROM. All responses carry COOP/COEP headers because mGBA-wasm uses
// Web Threads and requires cross-origin isolation.
//
//   node web/server.mjs [port]     (default port 8080)

import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { join, extname, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const port = Number(process.argv[2] ?? 8080);

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.wasm': 'application/wasm',
  '.gbc': 'application/octet-stream',
  '.gb': 'application/octet-stream',
  '.png': 'image/png',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json',
  '.map': 'application/json',
  '.ico': 'image/x-icon',
};

// url path -> file on disk
const ROUTES = {
  '/': 'web/index.html',
  '/index.html': 'web/index.html',
  '/mgba.js': 'node_modules/@thenick775/mgba-wasm/dist/mgba.js',
  '/mgba.wasm': 'node_modules/@thenick775/mgba-wasm/dist/mgba.wasm',
  '/mgba.wasm.map': 'node_modules/@thenick775/mgba-wasm/dist/mgba.wasm.map',
  '/morseboy1.gb': 'build/morseboy1.gb',
};

const server = createServer(async (req, res) => {
  // Cross-origin isolation (required by mGBA-wasm threads)
  res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
  res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
  res.setHeader('Cross-Origin-Resource-Policy', 'cross-origin');

  const url = new URL(req.url, `http://${req.headers.host ?? 'localhost'}`);
  const path = decodeURIComponent(url.pathname);

  const file = ROUTES[path] ?? (path.startsWith('/build/') ? path.slice(1) : null);
  if (!file || req.method !== 'GET' && req.method !== 'HEAD') {
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('not found');
    return;
  }

  try {
    const abs = normalize(join(root, file));
    const buf = await readFile(abs);
    res.writeHead(200, {
      'Content-Type': MIME[extname(abs)] ?? 'application/octet-stream',
      'Content-Length': buf.length,
      'Cache-Control': 'no-cache',
    });
    res.end(req.method === 'HEAD' ? undefined : buf);
  } catch {
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end(`not found: ${file} (did you run make?)`);
  }
});

server.listen(port, () => {
  console.log(`morseboy1 web emulator: http://localhost:${port}`);
  console.log('  ROM:  /morseboy1.gb   (build with "make" first)');
  console.log('  Note: needs COOP/COEP — open this origin, not a file:// URL');
});
