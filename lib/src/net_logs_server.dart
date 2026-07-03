import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'net_logs_interceptor.dart';

class NetLogsServer {
  final NetLogsInterceptor _interceptor;
  HttpServer? _server;
  int _port;
  bool _isRunning = false;
  final List<WebSocketChannel> _clients = [];
  void Function(int port)? _onStarted;

  NetLogsServer({
    required NetLogsInterceptor interceptor,
    int port = 8080,
    void Function(int port)? onStarted,
  })  : _interceptor = interceptor,
        _port = port,
        _onStarted = onStarted;

  bool get isRunning => _isRunning;
  int get port => _port;

  Future<void> start({int? port}) async {
    if (_isRunning) return;
    if (port != null) _port = port;

    final handler = shelf.Pipeline()
        .addMiddleware(shelf.logRequests())
        .addHandler(_router);

    final maxAttempts = 100;
    for (int i = 0; i < maxAttempts; i++) {
      try {
        _server = await shelf_io.serve(
          handler,
          InternetAddress.loopbackIPv4,
          _port + i,
        );
        if (i > 0) _port = _port + i;
        _isRunning = true;
        _interceptor.logStream.listen(_broadcastLog);
        _onStarted?.call(_port);
        return;
      } on SocketException catch (_) {
        continue;
      }
    }
    throw StateError('Could not find an available port after $maxAttempts attempts.');
  }

  Future<void> stop() async {
    for (final client in _clients) {
      await client.sink.close();
    }
    _clients.clear();
    await _server?.close(force: true);
    _isRunning = false;
  }

  FutureOr<shelf.Response> _router(shelf.Request request) {
    final path = request.url.path;

    if (request.method == 'GET' && path == '') {
      return shelf.Response.ok(_webUiHtml(), headers: {
        'content-type': 'text/html; charset=utf-8',
      });
    }

    if (request.method == 'GET' && path == 'api/logs') {
      final logs = _interceptor.logs.map((e) => e.toJson()).toList();
      return shelf.Response.ok(
        jsonEncode(logs),
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }

    if (path == 'ws') {
      final wsHandler = webSocketHandler((WebSocketChannel webSocket) {
        _clients.add(webSocket);
        webSocket.stream.listen(
          (_) {},
          onDone: () => _clients.remove(webSocket),
          onError: (_) => _clients.remove(webSocket),
        );
      });
      return wsHandler(request);
    }

    return shelf.Response.notFound('Not found');
  }

  void _broadcastLog(dynamic log) {
    final message = jsonEncode(log.toJson());
    for (final client in _clients.toList()) {
      try {
        client.sink.add(message);
      } catch (_) {
        _clients.remove(client);
      }
    }
  }

  static String _webUiHtml() {
    return r'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
<title>Net Logs</title>
<style>
  :root {
    --bg: #0a0a0c;
    --surface: #15151a;
    --surface-2: #1b1b21;
    --surface-hover: #202027;
    --border: #26262e;
    --border-subtle: #1e1e24;
    --text: #f2f2f5;
    --text-dim: #8b8b96;
    --text-faint: #55555f;
    --accent: #7c5cff;
    --accent-2: #5b8cff;
    --success: #34d399;
    --success-bg: #0f2a22;
    --warning: #fbbf24;
    --warning-bg: #2e2410;
    --error: #f87171;
    --error-bg: #2e1414;
    --info: #60a5fa;
    --info-bg: #10233d;
    --radius: 12px;
    --radius-sm: 6px;
  }
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
  html, body { height: 100%; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, 'Inter', 'Segoe UI', Roboto, sans-serif;
    background: var(--bg);
    color: var(--text);
    display: flex;
    flex-direction: column;
    font-size: 13px;
    overflow: hidden;
    -webkit-font-smoothing: antialiased;
  }

  /* ---------- Toolbar ---------- */
  .toolbar {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 10px 16px;
    background: rgba(21, 21, 26, 0.85);
    backdrop-filter: blur(12px);
    -webkit-backdrop-filter: blur(12px);
    border-bottom: 1px solid var(--border);
    flex-shrink: 0;
    z-index: 10;
  }
  .toolbar .logo {
    width: 26px; height: 26px;
    background: linear-gradient(135deg, var(--accent), var(--accent-2));
    border-radius: 8px;
    display: inline-flex; align-items: center; justify-content: center;
    font-size: 12px; font-weight: 800; color: #fff;
    box-shadow: 0 2px 10px rgba(124, 92, 255, 0.35);
    flex-shrink: 0;
  }
  .toolbar h1 { font-size: 14px; font-weight: 700; color: #fff; letter-spacing: -0.2px; white-space: nowrap; }
  .toolbar .stats {
    color: var(--text-dim); font-size: 11px; font-weight: 600;
    background: var(--surface-2); padding: 3px 9px; border-radius: 100px;
    border: 1px solid var(--border); white-space: nowrap; flex-shrink: 0;
  }
  .search-wrap { position: relative; flex: 1; max-width: 380px; min-width: 80px; }
  .search-wrap svg {
    position: absolute; left: 10px; top: 50%; transform: translateY(-50%);
    width: 14px; height: 14px; color: var(--text-faint); pointer-events: none;
  }
  .toolbar input[type="text"] {
    width: 100%; padding: 7px 10px 7px 30px;
    background: var(--surface-2); border: 1px solid var(--border);
    color: var(--text); border-radius: 100px; font-size: 12.5px; outline: none;
    transition: border-color .15s, background .15s;
  }
  .toolbar input[type="text"]:focus { border-color: var(--accent); background: var(--surface-hover); }
  .toolbar input[type="text"]::placeholder { color: var(--text-faint); }
  .toolbar button.icon-btn {
    display: inline-flex; align-items: center; justify-content: center;
    width: 30px; height: 30px; border: 1px solid var(--border); border-radius: 100px;
    cursor: pointer; background: var(--surface-2); color: var(--text-dim);
    transition: background .15s, color .15s, border-color .15s; flex-shrink: 0;
  }
  .toolbar button.icon-btn svg { width: 15px; height: 15px; }
  .toolbar button.icon-btn:hover { background: var(--error-bg); color: var(--error); border-color: #402020; }
  .toolbar button.icon-btn.active-sort { background: var(--info-bg); color: var(--info); border-color: #1a3a5a; }

  /* ---------- Layout ---------- */
  .main-area { display: flex; flex-direction: column; flex: 1; min-height: 0; }
  .table-container { flex: 1; overflow-y: auto; min-height: 100px; -webkit-overflow-scrolling: touch; position: relative; }

  /* ---------- Desktop table ---------- */
  .req-table { width: 100%; border-collapse: collapse; table-layout: fixed; }
  .req-table thead th {
    position: sticky; top: 0; z-index: 2; background: var(--bg);
    padding: 9px 12px; text-align: left; font-weight: 700; font-size: 10.5px;
    text-transform: uppercase; color: var(--text-faint); border-bottom: 1px solid var(--border);
    user-select: none; letter-spacing: 0.6px;
  }
  .req-table td {
    padding: 9px 12px; border-bottom: 1px solid var(--border-subtle);
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis; cursor: pointer;
  }
  .req-table tbody tr { transition: background .1s; }
  .req-table tbody tr:hover td { background: var(--surface); }
  .req-table tbody tr.selected td { background: var(--info-bg) !important; }
  .req-table .col-id { width: 44px; text-align: right; color: var(--text-faint); font-size: 11px; font-variant-numeric: tabular-nums; }
  .req-table .col-method { width: 82px; }
  .req-table .col-status { width: 68px; }
  .req-table .col-size { width: 76px; text-align: right; font-variant-numeric: tabular-nums; color: var(--text-dim); }
  .req-table .col-duration { width: 88px; text-align: right; font-variant-numeric: tabular-nums; color: var(--text-dim); }
  .req-table .col-time { width: 84px; font-size: 11px; color: var(--text-faint); font-variant-numeric: tabular-nums; }

  .method-badge, .status-badge {
    display: inline-flex; align-items: center; justify-content: center; padding: 3px 8px; border-radius: 6px;
    font-size: 10.5px; font-weight: 700; letter-spacing: 0.3px; line-height: 1;
  }
  .method-get { background: var(--info-bg); color: var(--info); }
  .method-post { background: var(--success-bg); color: var(--success); }
  .method-put { background: var(--warning-bg); color: var(--warning); }
  .method-patch { background: #10302e; color: #2dd4bf; }
  .method-delete { background: var(--error-bg); color: var(--error); }
  .method-options { background: #241a35; color: #c4b5fd; }
  .method-head { background: var(--surface-2); color: var(--text-dim); }

  .status-2xx { background: var(--success-bg); color: var(--success); }
  .status-3xx { background: var(--info-bg); color: var(--info); }
  .status-4xx { background: var(--warning-bg); color: var(--warning); }
  .status-5xx, .status-error { background: var(--error-bg); color: var(--error); }
  .status-pending { background: var(--surface-2); color: var(--text-faint); }

  /* ---------- Mobile cards ---------- */
  .log-cards { display: none; flex-direction: column; gap: 10px; padding: 12px; }
  .log-card {
    background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius);
    padding: 12px; cursor: pointer; transition: border-color .12s, background .12s, transform .1s;
    display: flex; flex-direction: column; gap: 8px;
  }
  .log-card:active { background: var(--surface-hover); transform: scale(0.99); }
  .log-card.selected { border-color: var(--accent); background: rgba(124, 92, 255, 0.05); }
  .log-card.card-2xx { border-left: 3px solid var(--success); }
  .log-card.card-3xx { border-left: 3px solid var(--info); }
  .log-card.card-4xx { border-left: 3px solid var(--warning); }
  .log-card.card-5xx, .log-card.card-error { border-left: 3px solid var(--error); }
  
  .log-card-top { display: flex; align-items: center; gap: 8px; width: 100%; }
  .log-card-time { margin-left: auto; font-size: 11px; color: var(--text-faint); font-variant-numeric: tabular-nums; font-weight: 500; }
  
  .log-card-url { 
    font-size: 13px; overflow-wrap: anywhere; line-height: 1.45; word-break: break-all;
    display: -webkit-box; -webkit-line-clamp: 3; -webkit-box-orient: vertical; overflow: hidden;
  }
  
  .log-card-meta {
    display: flex; align-items: center; gap: 12px; font-size: 11px; color: var(--text-dim);
    border-top: 1px solid var(--border-subtle); padding-top: 8px; font-variant-numeric: tabular-nums;
  }
  .log-card-meta-item { display: inline-flex; align-items: center; gap: 4px; }
  .log-card-meta-item .label { color: var(--text-faint); font-weight: 400; }
  .log-card-meta-item .value { font-weight: 600; color: var(--text); }
  .log-card-meta-dot { width: 3px; height: 3px; background: var(--text-faint); border-radius: 50%; opacity: 0.5; }

  .resize-handle { height: 5px; background: var(--border-subtle); cursor: ns-resize; flex-shrink: 0; position: relative; }
  .resize-handle::after {
    content: ''; position: absolute; left: 50%; top: 1.5px; width: 34px; height: 3px;
    background: var(--border); border-radius: 2px; transform: translateX(-50%); transition: background .15s;
  }
  .resize-handle:hover { background: var(--surface-2); }
  .resize-handle:hover::after { background: var(--accent); }

  /* ---------- Detail panel ---------- */
  #detail-panel {
    display: none; flex-direction: column; background: var(--surface);
    border-top: 1px solid var(--border); min-height: 140px; max-height: 70vh;
  }
  #detail-panel.open { display: flex; }
  .detail-header {
    display: flex; align-items: center; justify-content: space-between;
    border-bottom: 1px solid var(--border); background: var(--surface-2); flex-shrink: 0;
  }
  .detail-tabs { display: flex; padding: 0 6px; overflow-x: auto; }
  .detail-tabs button {
    padding: 10px 16px; background: none; border: none; color: var(--text-faint);
    cursor: pointer; font-size: 12px; font-weight: 600; border-bottom: 2px solid transparent;
    transition: color .15s, border-color .15s; white-space: nowrap;
  }
  .detail-tabs button:hover { color: var(--text-dim); }
  .detail-tabs button.active { color: #fff; border-bottom-color: var(--accent); }
  .detail-close {
    display: none; align-items: center; justify-content: center;
    width: 30px; height: 30px; margin-right: 8px; border: none; border-radius: 100px;
    background: var(--surface); color: var(--text-dim); cursor: pointer; flex-shrink: 0;
  }
  .detail-content { flex: 1; overflow: auto; padding: 0; display: none; -webkit-overflow-scrolling: touch; }
  .detail-content.active { display: block; }

  .detail-content pre {
    font-family: 'Cascadia Code', 'Fira Code', 'Consolas', 'JetBrains Mono', monospace;
    font-size: 12px; line-height: 1.65; padding: 14px 16px; margin: 0;
    white-space: pre-wrap; word-break: break-word; tab-size: 2;
  }
  .headers-table { width: 100%; border-collapse: collapse; }
  .headers-table td { padding: 7px 16px; border-bottom: 1px solid var(--border-subtle); vertical-align: top; font-size: 12px; }
  .headers-table td:first-child { font-weight: 600; color: var(--text-dim); width: 160px; white-space: nowrap; padding-right: 20px; }
  .headers-table .section-header td {
    font-weight: 700; color: var(--accent-2); padding-top: 16px; padding-bottom: 6px;
    font-size: 10.5px; text-transform: uppercase; letter-spacing: 0.6px; border-bottom: none;
  }

  .empty-state {
    display: flex; flex-direction: column; align-items: center; justify-content: center;
    height: 100%; color: var(--text-faint); gap: 10px; padding: 40px; text-align: center;
  }
  .empty-state svg { width: 34px; height: 34px; opacity: 0.4; }
  .empty-state .text { font-size: 13.5px; color: var(--text-dim); font-weight: 600; }
  .empty-state .sub { font-size: 11.5px; color: var(--text-faint); }

  .json-key { color: #9cdcfe; }
  .json-string { color: #ce9178; }
  .json-number { color: #b5cea8; }
  .json-boolean { color: #569cd6; }
  .json-null { color: #569cd6; }
  .json-bracket { color: #d4d4d4; }

  ::-webkit-scrollbar { width: 8px; height: 8px; }
  ::-webkit-scrollbar-track { background: transparent; }
  ::-webkit-scrollbar-thumb { background: var(--border); border-radius: 4px; }
  ::-webkit-scrollbar-thumb:hover { background: #3a3a44; }
  ::-webkit-scrollbar-corner { background: transparent; }

  .url-host { color: var(--text-faint); margin-right: 3px; font-weight: 500; }
  .url-path { color: var(--text); font-weight: 600; }

  .copy-btn {
    float: right; padding: 5px 12px; font-size: 11px; font-weight: 600;
    background: var(--surface-2); color: var(--text-dim); border: 1px solid var(--border);
    border-radius: 100px; cursor: pointer; margin: 10px 14px 0 0; transition: background .15s, color .15s;
  }
  .copy-btn:hover { background: var(--accent); color: #fff; border-color: var(--accent); }

  @keyframes fade-in { from { opacity: 0; background: rgba(124, 92, 255, 0.1); } to { opacity: 1; background: transparent; } }
  .row-new { animation: fade-in 0.5s ease-out; }

  /* ---------- Mobile ---------- */
  @media (max-width: 760px) {
    .toolbar h1 { display: none; }
    .toolbar .stats { order: 3; }

    .req-table { display: none; }
    .log-cards { display: flex; }

    #detail-panel {
      position: fixed; inset: 0; top: auto; max-height: 92vh; height: 92vh;
      border-radius: 16px 16px 0 0; z-index: 20; box-shadow: 0 -8px 30px rgba(0,0,0,0.5);
    }
    .detail-close { display: inline-flex; }
    .resize-handle { display: none; }
  }
</style>
</head>
<body>

<div class="toolbar">
  <span class="logo">N</span>
  <h1>Net Logs</h1>
  <div class="search-wrap">
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/></svg>
    <input type="text" id="filter" placeholder="Filter by URL..." spellcheck="false" oninput="applyFilter()">
  </div>
  <span class="stats" id="stats">Waiting...</span>
  <button onclick="toggleSort()" class="icon-btn" id="sort-btn" title="Sort order">
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m3 16 4 4 4-4"/><path d="M7 20V4"/><path d="m17 8-4-4-4 4"/><path d="M17 20V4"/></svg>
  </button>
  <button onclick="clearLogs()" class="icon-btn" title="Clear logs">
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/></svg>
  </button>
</div>

<div class="main-area">
  <div class="table-container" id="table-container">
    <table class="req-table">
      <thead>
        <tr>
          <th class="col-id">#</th>
          <th class="col-method">Method</th>
          <th>URL</th>
          <th class="col-status">Status</th>
          <th class="col-size">Size</th>
          <th class="col-duration">Duration</th>
          <th class="col-time">Time</th>
        </tr>
      </thead>
      <tbody id="log-body"></tbody>
    </table>
    <div class="log-cards" id="log-cards"></div>
    <div class="empty-state" id="empty-state">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/><path d="M3 3v5h5"/></svg>
      <div class="text">No network requests captured yet</div>
      <div class="sub">Make an HTTP request through Dio to see it here</div>
    </div>
  </div>

  <div class="resize-handle" id="resize-handle"></div>

  <div id="detail-panel">
    <div class="detail-header">
      <div class="detail-tabs">
        <button class="active" data-tab="headers" onclick="switchTab('headers', this)">Headers</button>
        <button data-tab="payload" onclick="switchTab('payload', this)">Payload</button>
        <button data-tab="response" onclick="switchTab('response', this)">Response</button>
      </div>
      <button class="detail-close" onclick="closeDetail()" title="Close">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>
      </button>
    </div>
    <div class="detail-content active" id="panel-headers"></div>
    <div class="detail-content" id="panel-payload"></div>
    <div class="detail-content" id="panel-response"></div>
  </div>
</div>

<script>
  const logs = [];
  let selectedId = null;
  let ws = null;
  let autoScroll = true;
  let sortOrder = 'newest'; // 'newest' or 'oldest'

  function connectWs() {
    const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
    ws = new WebSocket(proto + '//' + location.host + '/ws');
    ws.onmessage = (e) => {
      const log = JSON.parse(e.data);
      addLog(log);
    };
    ws.onclose = () => setTimeout(connectWs, 1000);
  }

  async function loadLogs() {
    try {
      const res = await fetch('/api/logs');
      const data = await res.json();
      for (const log of data) addLog(log);
    } catch (e) {
      console.error('Failed to load logs', e);
    }
  }

  function bodySize(log) {
    if (log.error) return 0;
    if (!log.responseBody) return 0;
    return new Blob([log.responseBody]).size;
  }

  function formatSize(bytes) {
    if (bytes === 0) return '-';
    if (bytes < 1024) return bytes + ' B';
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
    return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
  }

  function addLog(log) {
    if (sortOrder === 'newest') {
      logs.unshift(log);
    } else {
      logs.push(log);
    }

    const row = createRow(log);
    row.classList.add('row-new');
    const tbody = document.getElementById('log-body');
    if (sortOrder === 'newest') {
      tbody.insertBefore(row, tbody.firstChild);
    } else {
      tbody.appendChild(row);
    }

    const card = createCard(log);
    card.classList.add('row-new');
    const cards = document.getElementById('log-cards');
    if (sortOrder === 'newest') {
      cards.insertBefore(card, cards.firstChild);
    } else {
      cards.appendChild(card);
    }

    updateStats();
    toggleEmptyState();

    if (autoScroll) {
      const container = document.getElementById('table-container');
      container.scrollTop = container.scrollHeight;
    }
  }

  function toggleEmptyState() {
    document.getElementById('empty-state').style.display = logs.length ? 'none' : 'flex';
  }

  function renderAll() {
    document.getElementById('log-body').innerHTML = '';
    document.getElementById('log-cards').innerHTML = '';
    const items = sortOrder === 'newest' ? logs.slice().reverse() : logs;
    for (const log of items) {
      document.getElementById('log-body').appendChild(createRow(log));
      document.getElementById('log-cards').appendChild(createCard(log));
    }
    updateStats();
    toggleEmptyState();
  }

  function statusBadgeHtml(log) {
    if (log.statusCode) {
      const cat = Math.floor(log.statusCode / 100);
      return '<span class="status-badge status-' + cat + 'xx">' + log.statusCode + '</span>';
    }
    if (log.error) return '<span class="status-badge status-error">ERR</span>';
    return '<span class="status-badge status-pending">&hellip;</span>';
  }

  function matchesFilter(log, val) {
    if (!val) return true;
    const lower = val.toLowerCase();
    if (log.url.toLowerCase().includes(lower)) return true;
    if (log.name && log.name.toLowerCase().includes(lower)) return true;
    return false;
  }

  function createRow(log) {
    const tr = document.createElement('tr');
    tr.dataset.id = log.id;

    const url = new URL(log.url);
    const methodLower = log.method.toLowerCase();
    const methodBadge = '<span class="method-badge method-' + methodLower + '">' + log.method + '</span>';
    const badge = statusBadgeHtml(log);
    const size = bodySize(log);
    const time = new Date(log.timestamp).toLocaleTimeString();
    const duration = log.durationMs != null ? log.durationMs + ' ms' : '-';

    const val = (document.getElementById('filter').value || '').toLowerCase();
    if (!matchesFilter(log, val)) tr.style.display = 'none';

    const urlDisplay = log.name
      ? '<span class="url-host" style="font-weight:600;color:var(--text)">' + escapeHtml(log.name) + '</span> <span style="color:var(--text-faint);font-size:11px">' + escapeHtml(url.host + url.pathname + url.search) + '</span>'
      : '<span class="url-host">' + url.host + '</span><span class="url-path">' + url.pathname + url.search + '</span>';

    tr.innerHTML =
      '<td class="col-id">' + log.id + '</td>' +
      '<td class="col-method">' + methodBadge + '</td>' +
      '<td>' + urlDisplay + '</td>' +
      '<td class="col-status">' + badge + '</td>' +
      '<td class="col-size">' + formatSize(size) + '</td>' +
      '<td class="col-duration">' + duration + '</td>' +
      '<td class="col-time">' + time + '</td>';

    tr.onclick = () => selectLog(log.id);
    return tr;
  }

  function createCard(log) {
    const div = document.createElement('div');
    let cardClass = 'log-card';
    if (log.statusCode) {
      const cat = Math.floor(log.statusCode / 100);
      cardClass += ' card-' + cat + 'xx';
    } else if (log.error) {
      cardClass += ' card-error';
    }
    div.className = cardClass;
    div.dataset.id = log.id;

    const url = new URL(log.url);
    const methodLower = log.method.toLowerCase();
    const methodBadge = '<span class="method-badge method-' + methodLower + '">' + log.method + '</span>';
    const badge = statusBadgeHtml(log);
    const size = bodySize(log);
    const time = new Date(log.timestamp).toLocaleTimeString();
    const duration = log.durationMs != null ? log.durationMs + ' ms' : '-';

    const val = (document.getElementById('filter').value || '').toLowerCase();
    if (!matchesFilter(log, val)) div.style.display = 'none';

    const cardUrlDisplay = log.name
      ? '<div style="font-weight:600;color:var(--text);margin-bottom:2px">' + escapeHtml(log.name) + '</div><div style="font-size:11px;color:var(--text-faint)">' + escapeHtml(url.host + url.pathname + url.search) + '</div>'
      : '<span class="url-host">' + url.host + '</span><span class="url-path">' + url.pathname + url.search + '</span>';

    div.innerHTML =
      '<div class="log-card-top">' + 
        methodBadge + 
        badge + 
        '<span class="log-card-time">' + time + '</span>' + 
      '</div>' +
      '<div class="log-card-url">' + cardUrlDisplay + '</div>' +
      '<div class="log-card-meta">' + 
        '<div class="log-card-meta-item"><span class="label">size:</span><span class="value">' + formatSize(size) + '</span></div>' + 
        '<div class="log-card-meta-dot"></div>' + 
        '<div class="log-card-meta-item"><span class="label">time:</span><span class="value">' + duration + '</span></div>' + 
      '</div>';

    div.onclick = () => selectLog(log.id);
    return div;
  }

  function selectLog(id) {
    selectedId = id;
    document.querySelectorAll('#log-body tr.selected, #log-cards .log-card.selected').forEach(el => el.classList.remove('selected'));
    const row = document.querySelector('#log-body tr[data-id="' + id + '"]');
    if (row) row.classList.add('selected');
    const card = document.querySelector('#log-cards .log-card[data-id="' + id + '"]');
    if (card) card.classList.add('selected');

    const log = logs.find(l => l.id === id);
    if (!log) return;

    document.getElementById('detail-panel').classList.add('open');
    document.body.style.overflow = window.innerWidth <= 760 ? 'hidden' : '';

    // Headers
    let h = '<table class="headers-table">';
    if (log.name) h += '<tr><td>Name</td><td style="font-weight:600;color:var(--text)">' + escapeHtml(log.name) + '</td></tr>';
    h += '<tr><td>Request URL</td><td style="word-break:break-all">' + escapeHtml(log.url) + '</td></tr>';
    h += '<tr><td>Request Method</td><td><span class="method-badge method-' + log.method.toLowerCase() + '">' + log.method + '</span></td></tr>';
    if (log.durationMs != null) h += '<tr><td>Duration</td><td>' + log.durationMs + ' ms</td></tr>';

    const qp = log.queryParameters;
    if (qp && Object.keys(qp).length > 0) {
      h += '<tr class="section-header"><td colspan="2">Query Parameters</td></tr>';
      for (const [k, v] of Object.entries(qp)) {
        h += '<tr><td>' + escapeHtml(k) + '</td><td style="word-break:break-all">' + escapeHtml(v) + '</td></tr>';
      }
    }

    h += '<tr class="section-header"><td colspan="2">Request Headers</td></tr>';
    for (const [k, v] of Object.entries(log.requestHeaders || {})) {
      h += '<tr><td>' + escapeHtml(k) + '</td><td style="word-break:break-all">' + escapeHtml(v) + '</td></tr>';
    }
    if (log.responseHeaders) {
      h += '<tr class="section-header"><td colspan="2">Response Headers</td></tr>';
      for (const [k, v] of Object.entries(log.responseHeaders)) {
        h += '<tr><td>' + escapeHtml(k) + '</td><td style="word-break:break-all">' + escapeHtml(v) + '</td></tr>';
      }
    }
    h += '</table>';
    document.getElementById('panel-headers').innerHTML = h;

    // Payload
    const payloadEl = document.getElementById('panel-payload');
    if (log.requestBody) {
      const formatted = formatJson(log.requestBody);
      payloadEl.innerHTML = '<button class="copy-btn" onclick="copyText(this, \'' + escapeJs(log.requestBody) + '\')">Copy</button><pre>' + formatted + '</pre>';
    } else {
      payloadEl.innerHTML = '<div class="empty-state"><div class="text">No request body</div></div>';
    }

    // Response / Error tab
    const responseTabBtn = document.querySelector('.detail-tabs button[data-tab="response"]');
    const isError = !!log.error;
    responseTabBtn.textContent = isError ? 'Error' : 'Response';

    const responseEl = document.getElementById('panel-response');
    if (log.responseBody) {
      const formatted = formatJson(log.responseBody);
      responseEl.innerHTML = '<button class="copy-btn" onclick="copyText(this, \'' + escapeJs(log.responseBody) + '\')">Copy</button><pre>' + formatted + '</pre>';
    } else if (log.error) {
      responseEl.innerHTML = '<pre style="color:var(--error);padding:14px 16px">' + escapeHtml(log.error) + '</pre>';
    } else {
      responseEl.innerHTML = '<div class="empty-state"><div class="text">No response body</div></div>';
    }

    const activeTab = document.querySelector('.detail-tabs .active');
    if (activeTab) switchTab(activeTab.dataset.tab, activeTab);
  }

  function closeDetail() {
    document.getElementById('detail-panel').classList.remove('open');
    document.body.style.overflow = '';
    document.querySelectorAll('#log-body tr.selected, #log-cards .log-card.selected').forEach(el => el.classList.remove('selected'));
    selectedId = null;
  }

  function switchTab(tab, btn) {
    document.querySelectorAll('.detail-tabs button').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    document.querySelectorAll('.detail-content').forEach(el => el.classList.remove('active'));
    document.getElementById('panel-' + tab).classList.add('active');
  }

  function applyFilter() {
    const val = (document.getElementById('filter').value || '').toLowerCase();
    let visible = 0;
    document.querySelectorAll('#log-body tr').forEach(tr => {
      const log = logs.find(l => l.id == tr.dataset.id);
      if (!log) return;
      const match = matchesFilter(log, val);
      tr.style.display = match ? '' : 'none';
    });
    document.querySelectorAll('#log-cards .log-card').forEach(card => {
      const log = logs.find(l => l.id == card.dataset.id);
      if (!log) return;
      const match = matchesFilter(log, val);
      card.style.display = match ? '' : 'none';
      if (match) visible++;
    });
    document.getElementById('stats').textContent = visible + ' / ' + logs.length;
  }

  function toggleSort() {
    sortOrder = sortOrder === 'newest' ? 'oldest' : 'newest';
    const btn = document.getElementById('sort-btn');
    btn.classList.toggle('active-sort', sortOrder === 'oldest');
    btn.title = sortOrder === 'newest' ? 'Newest first' : 'Oldest first';
    renderAll();
    if (selectedId !== null) selectLog(selectedId);
  }

  function clearLogs() {
    logs.length = 0;
    document.getElementById('log-body').innerHTML = '';
    document.getElementById('log-cards').innerHTML = '';
    closeDetail();
    document.getElementById('detail-panel').classList.remove('open');
    updateStats();
    toggleEmptyState();
    fetch('/api/logs', { method: 'DELETE' }).catch(() => {});
  }

  function updateStats() {
    document.getElementById('stats').textContent = logs.length + ' requests';
  }

  function escapeHtml(str) {
    if (!str) return '';
    return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function escapeJs(str) {
    if (!str) return '';
    return str.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\n/g, '\\n').replace(/\r/g, '\\r');
  }

  function formatJson(text) {
    if (!text) return '';
    let obj;
    try {
      obj = JSON.parse(text);
    } catch (_) {
      try {
        obj = parseLoose(text);
      } catch (__) {
        return escapeHtml(text);
      }
    }
    const json = JSON.stringify(obj, null, 2);
    return syntaxHighlight(json);
  }

  function parseLoose(text) {
    let i = 0;
    const s = text;

    function skipWs() { while (i < s.length && /\s/.test(s[i])) i++; }

    // Lenient parser methods
    function parseValue() {
      skipWs();
      if (s[i] === '{') return parseObject();
      if (s[i] === '[') return parseArray();
      if (s[i] === '"' || s[i] === "'") return parseQuoted();
      return parseBare();
    }

    function parseQuoted() {
      const quote = s[i];
      i++;
      let out = '';
      while (i < s.length && s[i] !== quote) {
        if (s[i] === '\\' && i + 1 < s.length) { out += s[i + 1]; i += 2; }
        else { out += s[i]; i++; }
      }
      i++;
      return out;
    }

    function parseBare() {
      let start = i;
      while (i < s.length && s[i] !== ',' && s[i] !== '}' && s[i] !== ']') i++;
      const raw = s.slice(start, i).trim();
      if (raw === 'true') return true;
      if (raw === 'false') return false;
      if (raw === 'null') return null;
      if (raw !== '' && !isNaN(Number(raw))) return Number(raw);
      return raw;
    }

    function parseKey() {
      skipWs();
      if (s[i] === '"' || s[i] === "'") return parseQuoted();
      let start = i;
      while (i < s.length && s[i] !== ':') i++;
      return s.slice(start, i).trim();
    }

    function parseObject() {
      i++;
      const out = {};
      skipWs();
      if (s[i] === '}') { i++; return out; }
      while (i < s.length) {
        const key = parseKey();
        skipWs();
        if (s[i] === ':') i++;
        const value = parseValue();
        out[key] = value;
        skipWs();
        if (s[i] === ',') { i++; skipWs(); continue; }
        if (s[i] === '}') { i++; break; }
        break;
      }
      return out;
    }

    function parseArray() {
      i++;
      const out = [];
      skipWs();
      if (s[i] === ']') { i++; return out; }
      while (i < s.length) {
        out.push(parseValue());
        skipWs();
        if (s[i] === ',') { i++; skipWs(); continue; }
        if (s[i] === ']') { i++; break; }
        break;
      }
      return out;
    }

    skipWs();
    return parseValue();
  }

  function syntaxHighlight(json) {
    return escapeHtml(json).replace(
      /("(?:[^"\\]|\\.)*")\s*:/g,
      '<span class="json-key">$1</span>:'
    ).replace(
      /"((?:[^"\\]|\\.)*)"/g,
      '<span class="json-string">"$1"</span>'
    ).replace(
      /\b(-?\d+\.?\d*([eE][+-]?\d+)?)\b/g,
      '<span class="json-number">$1</span>'
    ).replace(
      /\b(true|false)\b/g,
      '<span class="json-boolean">$1</span>'
    ).replace(
      /\bnull\b/g,
      '<span class="json-null">null</span>'
    ).replace(
      /([\{\}\]\[])/g,
      '<span class="json-bracket">$1</span>'
    );
  }

  function copyText(btn, text) {
    navigator.clipboard.writeText(text).then(() => {
      const orig = btn.textContent;
      btn.textContent = 'Copied!';
      setTimeout(() => btn.textContent = orig, 1200);
    }).catch(() => {});
  }

  // Resize handle (desktop only)
  const handle = document.getElementById('resize-handle');
  const panel = document.getElementById('detail-panel');
  let isResizing = false;

  handle.addEventListener('mousedown', () => {
    isResizing = true;
    document.body.style.cursor = 'ns-resize';
    document.body.style.userSelect = 'none';
  });

  document.addEventListener('mousemove', (e) => {
    if (!isResizing) return;
    const mainArea = document.querySelector('.main-area');
    const rect = mainArea.getBoundingClientRect();
    const panelHeight = Math.min(Math.max(rect.bottom - e.clientY, 140), rect.height * 0.7);
    panel.style.height = panelHeight + 'px';
  });

  document.addEventListener('mouseup', () => {
    if (isResizing) {
      isResizing = false;
      document.body.style.cursor = '';
      document.body.style.userSelect = '';
    }
  });

  toggleEmptyState();
  connectWs();
  loadLogs();
</script>
</body>
</html>''';
  }
}
