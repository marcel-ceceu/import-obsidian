#!/usr/bin/env node
/**
 * Helper mínimo para o PWA Vault Copy abrir pastas no Explorer (Windows).
 * Uso: node folder-opener.mjs  |  duplo-clique em Iniciar-FolderOpener.cmd
 * Porta padrão: 5380
 */
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';

const PORT = Number(process.env.PORT || 5380);
const HOST = '127.0.0.1';

function corsHeaders(extra = {}) {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Private-Network': 'true',
    ...extra,
  };
}

function sendJson(res, status, obj) {
  res.writeHead(status, { 'Content-Type': 'application/json', ...corsHeaders() });
  res.end(JSON.stringify(obj));
}

function normalizeFolder(raw) {
  if (!raw || typeof raw !== 'string') return null;
  const normalized = path.normalize(decodeURIComponent(raw.trim()));
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

function openFolderFromRequest(rawPath, res, asHtml) {
  const folder = normalizeFolder(rawPath);
  if (!folder) {
    if (asHtml) {
      res.writeHead(400, { 'Content-Type': 'text/html; charset=utf-8', ...corsHeaders() });
      res.end('<p>folderPath absoluto obrigatório.</p>');
      return;
    }
    sendJson(res, 400, { ok: false, error: 'folderPath absoluto obrigatório' });
    return;
  }
  if (!fs.existsSync(folder) || !fs.statSync(folder).isDirectory()) {
    if (asHtml) {
      res.writeHead(404, { 'Content-Type': 'text/html; charset=utf-8', ...corsHeaders() });
      res.end(`<p>Pasta não encontrada:</p><pre>${folder}</pre>`);
      return;
    }
    sendJson(res, 404, { ok: false, error: 'pasta não encontrada', folderPath: folder });
    return;
  }
  openInExplorer(folder);
  if (asHtml) {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', ...corsHeaders() });
    res.end(`<!DOCTYPE html><html lang="pt-BR"><head><meta charset="utf-8"><title>Pasta aberta</title></head><body style="font-family:sans-serif;padding:24px"><h1>Pasta aberta no Explorer</h1><p><code>${folder}</code></p><p>Pode fechar esta aba.</p></body></html>`);
    return;
  }
  sendJson(res, 200, { ok: true, folderPath: folder });
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

  const reqUrl = new URL(req.url || '/', `http://${HOST}`);

  if (req.method === 'GET' && reqUrl.pathname === '/api/health') {
    sendJson(res, 200, { ok: true, service: 'folder-opener', port: PORT });
    return;
  }

  if (req.method === 'GET' && reqUrl.pathname === '/open') {
    openFolderFromRequest(reqUrl.searchParams.get('folderPath') || '', res, true);
    return;
  }

  if (req.method === 'GET' && reqUrl.pathname === '/api/open-folder') {
    openFolderFromRequest(reqUrl.searchParams.get('folderPath') || '', res, false);
    return;
  }

  if (req.method === 'POST' && reqUrl.pathname === '/api/open-folder') {
    try {
      const { folderPath } = await readJsonBody(req);
      openFolderFromRequest(folderPath, res, false);
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
  console.log('  GET  /open?folderPath=...');
  console.log('  POST /api/open-folder  { "folderPath": "..." }');
  console.log('');
});
