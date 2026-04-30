# Tirekicker -- Cloudflare Worker

Multi-path Worker for the tirekicker script delivery.

## Routes

| Path | Method | Behavior |
|---|---|---|
| `/` | GET | UA detection: `curl`/`bash` -> raw `run.sh` body; browser -> HTML landing (EN/ES toggle, copy-to-clipboard) |
| `/win`, `/win.ps1` | GET | raw `run.ps1` body (Windows `irm \| iex`) |
| `/run.sh` | GET | raw `run.sh` body (explicit) |
| `/api/report` | POST | receives report JSON from script -> sends Telegram |
| `/api/relay-url` | POST | Tier 2 alarm: receives a file URL -> sends Telegram |

## Delivery topology (v0)

```
script -> [Tier 1] CF Worker /api/report -> Telegram
        -> (fail) [Tier 2] file upload (0x0.st > catbox > transfer.sh)
                  -> /api/relay-url -> Telegram (URL alarm)
        -> (fail) [Tier 3] screen fallback (URL + JSON path)
```

n8n forward is **commented out** in `index.js` `handleReport`. To re-enable: uncomment the block and set the `N8N_WEBHOOK_URL` secret.

## Deploy

```bash
cd deploy/cf-worker
npm i -g wrangler
wrangler login

# 1. Create KV namespace for rate-limit
wrangler kv namespace create RATE_KV
# Paste the returned id into wrangler.toml under [[kv_namespaces]].id

# 2. Set secrets
wrangler secret put TELEGRAM_BOT_TOKEN
wrangler secret put TELEGRAM_CHAT_ID
# Optional:
# wrangler secret put HMAC_KEY
# wrangler secret put N8N_WEBHOOK_URL

# 3. Deploy
wrangler deploy

# 4. Bind tk.c3t.com.tr custom domain via dashboard:
#    Workers & Pages -> tirekicker-relay -> Settings -> Triggers
#    -> Custom Domains -> Add Custom Domain -> tk.c3t.com.tr
```

## Notes

- **Rate limit:** 100 POST per minute per IP (KV-based). 4 devices testing concurrently fits comfortably.
- **HMAC verification:** present as placeholder header on script side; **not enforced** in v0. Real protection is rate-limit + fixed Telegram chat.
- **`curl -fsSL https://tk.c3t.com.tr | bash`** works because root path detects curl UA and serves the script body directly.
- **n8n disabled:** the user's n8n setup is not working; we bypass it. `index.js` keeps the n8n forward as a commented block for future re-enablement.
