// Tirekicker CF Worker
// Routes:
//   GET  /                  -> UA detect: curl/bash -> run.sh body; browser -> HTML landing
//   GET  /win, /win.ps1     -> run.ps1 body (Windows)
//   GET  /run.sh            -> run.sh body (explicit)
//   POST /api/report        -> receives report JSON, sends Telegram
//   POST /api/relay-url     -> Tier 2 alarm: file URL relayed to Telegram
//
// Rate limit: 100 POST per minute per IP (KV).
// HMAC verification: not enforced in v0 (placeholder header forwarded).
//
// Secrets (wrangler secret put):
//   TELEGRAM_BOT_TOKEN
//   TELEGRAM_CHAT_ID
//   HMAC_KEY
//   N8N_WEBHOOK_URL   (optional; currently disabled in handleReport)

const RAW_BASE = 'https://raw.githubusercontent.com/C3T-Teknoloji-AS/tirekicker/main';

export default {
  async fetch(request, env, _ctx) {
    const url = new URL(request.url);
    const method = request.method;

    // Rate limit (POST only, KV-based)
    if (env.RATE_KV && method === 'POST') {
      const ip = request.headers.get('CF-Connecting-IP') || 'unknown';
      const minute = Math.floor(Date.now() / 60000);
      const key = `rl:${ip}:${minute}`;
      const cnt = parseInt((await env.RATE_KV.get(key)) || '0', 10);
      if (cnt >= 100) {
        return new Response('rate limited', { status: 429 });
      }
      await env.RATE_KV.put(key, String(cnt + 1), { expirationTtl: 120 });
    }

    if (method === 'GET' && url.pathname === '/') {
      const ua = request.headers.get('User-Agent') || '';
      if (/curl|wget|bash|python|libcurl/i.test(ua)) {
        const r = await fetch(`${RAW_BASE}/run.sh`);
        return new Response(r.body, {
          status: r.status,
          headers: { 'Content-Type': 'text/x-shellscript; charset=utf-8' },
        });
      }
      return new Response(renderLanding(), {
        headers: { 'Content-Type': 'text/html; charset=utf-8' },
      });
    }

    if (method === 'GET' && (url.pathname === '/win' || url.pathname === '/win.ps1')) {
      const r = await fetch(`${RAW_BASE}/run.ps1`);
      return new Response(r.body, {
        status: r.status,
        headers: { 'Content-Type': 'text/plain; charset=utf-8' },
      });
    }

    if (method === 'GET' && url.pathname === '/run.sh') {
      const r = await fetch(`${RAW_BASE}/run.sh`);
      return new Response(r.body, {
        status: r.status,
        headers: { 'Content-Type': 'text/x-shellscript; charset=utf-8' },
      });
    }

    if (method === 'POST' && url.pathname === '/api/report') {
      return await handleReport(request, env);
    }
    if (method === 'POST' && url.pathname === '/api/relay-url') {
      return await handleRelayUrl(request, env);
    }

    return new Response('not found', { status: 404 });
  },
};

async function handleReport(request, env) {
  const body = await request.text();
  let payload;
  try {
    payload = JSON.parse(body);
  } catch {
    return new Response('bad json', { status: 400 });
  }

  // ============================================================
  // n8n forward -- DISABLED (n8n not in use in v0)
  // Re-enable by uncommenting and setting N8N_WEBHOOK_URL secret.
  // ============================================================
  // let n8nOk = false;
  // if (env.N8N_WEBHOOK_URL) {
  //   try {
  //     const r = await fetch(env.N8N_WEBHOOK_URL, {
  //       method: 'POST',
  //       headers: { 'Content-Type': 'application/json' },
  //       body,
  //     });
  //     n8nOk = r.ok;
  //   } catch {}
  // }
  // ============================================================

  // Telegram (primary delivery)
  let tgOk = false;
  if (env.TELEGRAM_BOT_TOKEN && env.TELEGRAM_CHAT_ID) {
    const msg = formatTelegramMessage(payload);
    try {
      const r = await fetch(
        `https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/sendMessage`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            chat_id: env.TELEGRAM_CHAT_ID,
            text: msg,
            parse_mode: 'Markdown',
          }),
        }
      );
      tgOk = r.ok;
    } catch {}
  }

  return new Response(JSON.stringify({ ok: tgOk }), {
    status: tgOk ? 200 : 502,
    headers: { 'Content-Type': 'application/json' },
  });
}

async function handleRelayUrl(request, env) {
  let body;
  try {
    body = await request.json();
  } catch {
    return new Response('bad json', { status: 400 });
  }
  const { url: fileUrl, fingerprint, report_id } = body;
  if (!fileUrl) return new Response('missing url', { status: 400 });

  if (env.TELEGRAM_BOT_TOKEN && env.TELEGRAM_CHAT_ID) {
    const msg =
      '*Tirekicker -- Tier 2 (file upload)*\n\n' +
      'Report ID: `' + (report_id || 'n/a') + '`\n' +
      'Fingerprint: `' + (fingerprint || 'n/a') + '`\n' +
      'File: ' + fileUrl + '\n\n' +
      'Direct POST failed. Fetch the file manually.';
    try {
      await fetch(
        `https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/sendMessage`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            chat_id: env.TELEGRAM_CHAT_ID,
            text: msg,
            parse_mode: 'Markdown',
          }),
        }
      );
    } catch {}
  }
  return new Response(JSON.stringify({ ok: true }), {
    headers: { 'Content-Type': 'application/json' },
  });
}

function formatTelegramMessage(p) {
  const fp = p.fingerprint || 'unknown';
  const dur = p.duration_sec || 0;
  const os = (p.os && p.os.pretty_name) || 'unknown';
  const arch = (p.client && p.client.arch) || '?';
  const cpu = (p.system && p.system.cpu && p.system.cpu.model) || '?';
  const ramGB =
    p.system && p.system.ram && p.system.ram.total_bytes
      ? Math.round(p.system.ram.total_bytes / (1024 ** 3))
      : '?';
  const ramType = (p.system && p.system.ram && p.system.ram.type) || '?';
  const ramSpeed = (p.system && p.system.ram && p.system.ram.speed_mts) || '?';
  const board = (p.system && p.system.board && p.system.board.product) || '?';
  const gpuDev = p.gpu && p.gpu.devices && p.gpu.devices[0];
  const gpu = gpuDev ? gpuDev.name : (p.gpu && p.gpu.detected === false ? 'NOT DETECTED' : '?');
  const drv = (p.gpu && p.gpu.stack && p.gpu.stack.driver_version) || '?';
  const cuda = (p.gpu && p.gpu.stack && p.gpu.stack.cuda_version) || '?';
  const ptVer = (p.gpu && p.gpu.stack && p.gpu.stack.pytorch_version) || '?';
  const peakG = (p.ai_smoke && p.ai_smoke.peak_gflops) ?? 'n/a';
  const writeMB = (p.storage_bench && p.storage_bench.write_mbps) ?? 'n/a';
  const readMB = (p.storage_bench && p.storage_bench.read_mbps) ?? 'n/a';
  const nvme = p.nvme_smart && p.nvme_smart.devices && p.nvme_smart.devices[0];
  const poh = nvme ? (nvme.power_on_hours ?? 'n/a') : 'n/a';
  const pctUsed = nvme ? (nvme.percentage_used_pct ?? 'n/a') : 'n/a';
  const mediaErr = nvme ? (nvme.media_errors ?? 'n/a') : 'n/a';
  const hwidMM = p.hwid && p.hwid.hwid_mismatch ? 'MISMATCH' : 'OK';
  const errCount = (p.errors && p.errors.length) || 0;
  const uptime = (p.freshness && p.freshness.uptime_sec) ?? 'n/a';
  const tempLoad = p.thermal_power && p.thermal_power.under_load ? p.thermal_power.under_load.gpu_temp_c : 'n/a';
  const tempAfter = p.thermal_power && p.thermal_power.after_load ? p.thermal_power.after_load.gpu_temp_c : 'n/a';
  const dh = (p.dmesg && p.dmesg.pattern_hits) || [];
  const findHit = (n) => (dh.find((h) => h.pattern === n) || {}).count || 0;

  const lines = [
    '*Tirekicker* `' + fp + '` (' + dur + 's)',
    '',
    '*OS*: ' + os + ' (' + arch + ')',
    '*Board*: ' + board,
    '*CPU*: ' + cpu,
    '*RAM*: ' + ramGB + ' GB ' + ramType + ' ' + ramSpeed + ' MT/s',
    '*GPU*: ' + gpu,
    '*Driver*: ' + drv + ' | *CUDA*: ' + cuda + ' | *PyTorch*: ' + ptVer,
    '*HWID*: ' + hwidMM,
    '',
    '*AI smoke*: ' + peakG + ' GFLOPS peak',
    '*Storage*: ' + writeMB + ' MB/s W, ' + readMB + ' MB/s R',
    '*NVMe*: ' + poh + 'h on, ' + pctUsed + '% used, ' + mediaErr + ' media errs',
    '*Thermal*: ' + tempLoad + 'C load -> ' + tempAfter + 'C after',
    '*Uptime*: ' + uptime + 's',
    '*dmesg*: MCE ' + findHit('MCE') + ', PCIe ' + findHit('PCIe_error') + ', throttle ' + findHit('thermal_throttle'),
    '*Errors*: ' + errCount,
    '',
    'Reply *go ahead, pay* if OK, *stop* if not.',
  ];
  return lines.join('\n');
}

function renderLanding() {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Tirekicker</title>
  <style>
    :root { color-scheme: dark; }
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #0d0d10; color: #eee; margin: 0; padding: 2rem 1rem; max-width: 640px; margin: auto; line-height: 1.5; }
    h1 { font-size: 1.4rem; margin: 0 0 0.5rem; }
    .lang { float: right; font-size: 0.9rem; }
    .lang a { color: #6cf; text-decoration: none; }
    p.sub { color: #aaa; margin-top: 0; }
    button { display: block; width: 100%; padding: 1.1rem; margin: 0.6rem 0; font-size: 1.05rem; background: #1c7c4d; color: #fff; border: 0; border-radius: 8px; cursor: pointer; transition: background 0.15s; }
    button:hover { background: #259c61; }
    button:active { background: #14633c; }
    pre { background: #000; padding: 1rem; border-radius: 6px; overflow-x: auto; font-size: 0.85rem; color: #b6f5b6; min-height: 1rem; }
    .hint { color: #aaa; font-size: 0.9rem; }
    .ok { color: #6c6; font-size: 0.85rem; height: 1rem; margin: 0.4rem 0; }
  </style>
</head>
<body>
  <span class="lang"><a href="#" id="toggleLang">Espanol</a></span>
  <h1 id="title">Tirekicker</h1>
  <p class="sub" id="subtitle">Device pre-purchase check. Pick your OS, the command will copy to clipboard. Paste it into a terminal, press Enter.</p>

  <button id="btnLinux">Linux</button>
  <button id="btnWin">Windows (PowerShell as Administrator)</button>

  <p class="ok" id="copied"></p>
  <pre id="cmdOut"></pre>

  <p class="hint" id="hint">Then send 6 photos to the buyer on Telegram (front, back, bottom, I/O panel, adapter label, serial sticker). Wait for the go-ahead before paying.</p>

  <script>
    var cmds = {
      linux: 'curl -fsSL https://tk.c3t.com.tr | bash',
      win: 'irm https://tk.c3t.com.tr/win | iex'
    };
    var i18n = {
      en: {
        title: 'Tirekicker',
        sub: 'Device pre-purchase check. Pick your OS, the command will copy to clipboard. Paste it into a terminal, press Enter.',
        linux: 'Linux',
        win: 'Windows (PowerShell as Administrator)',
        hint: 'Then send 6 photos to the buyer on Telegram (front, back, bottom, I/O panel, adapter label, serial sticker). Wait for the go-ahead before paying.',
        toggle: 'Espanol',
        copied: 'Copied. Paste in terminal.'
      },
      es: {
        title: 'Tirekicker',
        sub: 'Comprobacion previa del dispositivo. Elige el SO; el comando se copia al portapapeles. Pegalo en una terminal y pulsa Enter.',
        linux: 'Linux',
        win: 'Windows (PowerShell como Administrador)',
        hint: 'Luego envia 6 fotos al comprador por Telegram (frontal, trasera, inferior, panel I/O, etiqueta del adaptador, pegatina de serie). Espera el visto bueno antes de pagar.',
        toggle: 'English',
        copied: 'Copiado. Pega en la terminal.'
      }
    };
    var lang = 'en';
    function applyLang() {
      var t = i18n[lang];
      document.getElementById('title').textContent = t.title;
      document.getElementById('subtitle').textContent = t.sub;
      document.getElementById('btnLinux').textContent = t.linux;
      document.getElementById('btnWin').textContent = t.win;
      document.getElementById('hint').textContent = t.hint;
      document.getElementById('toggleLang').textContent = t.toggle;
    }
    document.getElementById('toggleLang').onclick = function (e) {
      e.preventDefault();
      lang = lang === 'en' ? 'es' : 'en';
      applyLang();
      document.getElementById('copied').textContent = '';
    };
    function copy(cmd) {
      document.getElementById('cmdOut').textContent = cmd;
      if (navigator.clipboard) {
        navigator.clipboard.writeText(cmd).then(function () {
          document.getElementById('copied').textContent = i18n[lang].copied;
        }).catch(function () {});
      }
    }
    document.getElementById('btnLinux').onclick = function () { copy(cmds.linux); };
    document.getElementById('btnWin').onclick = function () { copy(cmds.win); };
  </script>
</body>
</html>`;
}
