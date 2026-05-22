#!/usr/bin/env node
/**
 * Helper mínimo para o PWA Vault Copy abrir pastas no Explorer (Windows).
 * Uso: node folder-opener.mjs
 * Porta padrão: 5380 (override: PORT=5380 node folder-opener.mjs)
 */
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
const PORT = Number(process.env.PORT || 5380);
const HOST = '127.0.0.1';

function corsHeaders() {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
  };
}

function sendJson(res, status, obj) {
  res.writeHead(status, { 'Content-Type': 'application/json', ...corsHeaders() });
  res.end(JSON.stringify(obj));
}

function normalizeFolder(raw) {
  if (!raw || typeof raw !== 'string') return null;
  const normalized = path.normalize(raw.trim());
  if (!path.isAbsolute(normalized)) return null;
  return normalized;
}

function openInExplorer(folderPath) {
  if (process.platform === 'win32') {
    spawn('explorer.exe', [folderPath], { detached: true, stdio: 'ignore', windowsHide: true }).unref();
    return;
  }
  const cmd = process.platform === 'darwin' ? 'open' : 'xdg-open';
  spawn(cmd, [folderPath], { detached: true, stdio: 'ignore', windowsHide: true }).unref();
}

function readJsonBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', (chunk) => {
      body += chunk;
      if (body.length > 4096) {
        reject(new Error('payload grande demais'));
        req.destroy();
      }
    });
    req.on('end', () => {
      try {
        resolve(body ? JSON.parse(body) : {});
      } catch (e) {
        reject(e);
      }
    });
    req.on('error', reject);
  });
}

const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') {
    res.writeHead(204, corsHeaders());
    res.end();
    return;
  }

  if (req.method === 'GET' && req.url === '/api/health') {
    sendJson(res, 200, { ok: true, service: 'folder-opener', port: PORT });
    return;
  }

  if (req.method === 'POST' && req.url === '/api/open-folder') {
    try {
      const { folderPath } = await readJsonBody(req);
      const folder = normalizeFolder(folderPath);
      if (!folder) {
        sendJson(res, 400, { ok: false, error: 'folderPath absoluto obrigatório' });
        return;
      }
      if (!fs.existsSync(folder) || !fs.statSync(folder).isDirectory()) {
        sendJson(res, 404, { ok: false, error: 'pasta não encontrada', folderPath: folder });
        return;
      }
      openInExplorer(folder);
      sendJson(res, 200, { ok: true, folderPath: folder });
    } catch (e) {
      sendJson(res, 500, { ok: false, error: String(e.message || e) });
    }
    return;
  }

  sendJson(res, 404, { ok: false, error: 'not found' });
});

server.listen(PORT, HOST, () => {
  console.log('');
  console.log(`  folder-opener em http://${HOST}:${PORT}`);
  console.log('  POST /api/open-folder  { "folderPath": "C:\\\\Users\\\\...\\\\resultados-..." }');
  console.log('');
});
