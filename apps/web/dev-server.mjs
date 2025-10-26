import { createServer } from 'node:http';
import { stat, readFile } from 'node:fs/promises';
import { extname, join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const publicDir = resolve(__dirname, 'public');
const srcDir = resolve(__dirname, 'src');
const PORT = Number(process.env.WEB_PORT ?? 5173);

const mimeTypes = {
  '.html': 'text/html',
  '.js': 'application/javascript',
  '.mjs': 'application/javascript',
  '.css': 'text/css',
  '.json': 'application/json',
  '.ico': 'image/x-icon'
};

createServer(async (req, res) => {
  try {
    if (!req.url) {
      res.writeHead(400);
      res.end('Bad request');
      return;
    }
    const cleanUrl = req.url.split('?')[0];
    const relative = cleanUrl.startsWith('/') ? cleanUrl.slice(1) : cleanUrl;
    const srcRelative = relative.startsWith('src/') ? relative.slice(4) : relative;
    const candidates = [join(publicDir, relative), join(srcDir, srcRelative)];
    let filePath;
    for (const candidate of candidates) {
      try {
        const stats = await stat(candidate);
        if (stats.isFile()) {
          filePath = candidate;
          break;
        }
      } catch (error) {
        // ignore
      }
    }
    if (!filePath) {
      filePath = join(publicDir, 'index.html');
    }
    const ext = extname(filePath);
    res.writeHead(200, { 'Content-Type': mimeTypes[ext] ?? 'text/plain' });
    const content = await readFile(filePath);
    res.end(content);
  } catch (error) {
    res.writeHead(500);
    res.end(error.message);
  }
}).listen(PORT, () => {
  console.log(`Web dev server running on http://localhost:${PORT}`);
});
