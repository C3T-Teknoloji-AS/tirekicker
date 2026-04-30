# tirekicker — Memory

> Session-to-session devamlılık dosyası. Her session sonunda güncellenir.

## Decisions Log

### 2026-04-30 — Session 001 (proje açılışı)

**Bağlam:** Yurtdışından bir AI cihaz (örn. ASUS Ascent GX10) satın alınacak, satıcının yanına gidecek arkadaş teknik değil. Cihazı uzaktan teşhis edip "al / alma" kararını verebilmek için tek satır komutla çalışan, sonuçları bize POST eden bir script gerekiyor.

**Alınan kararlar:**

| # | Konu | Karar | Gerekçe |
|---|---|---|---|
| 1 | Proje adı | `tirekicker` | "Tire kicking" = satın almadan önce inceleme metaforu, akılda kalıcı, İngilizce kullanıcılara da doğal |
| 2 | Konum | `c3t/repos/tirekicker` + `c3t/projects/tirekicker/README.md` (meta) | c3t standart yapısı: kendi repo'su olan projeler `repos/`'a klonlanır |
| 3 | GitHub org | `C3T-Teknoloji-AS` | Kullanıcı manuel oluşturuyor |
| 4 | Görünürlük | Public | Curl one-liner private repoda token zorunlu kılar; satıcı arkadaşa yük |
| 5 | Sonuç kanalı | n8n webhook → Telegram | n8n zaten ayakta, en az ek altyapı |
| 6 | Script dili | Bash (Linux/macOS), PowerShell (Windows faz 2) | Bağımlılıksız, default kurulu |
| 7 | Script çıktı dili | İngilizce | — |
| 8 | README dili | **EN + ES iki dilli** (önce EN, sonra ES) | İlk hedef ülke İspanya |
| 9 | OS önceliği | Linux %90, Windows %10, macOS lazım olabilir | AI cihazların büyük çoğunluğu Linux-based |
| 10 | Kullanıcıya söylenen süre | 5–10 dakika | Gerçek çalışma 60–180sn ama güvenli pay verildi |
| 11 | README üslubu | Çok yalın: açık + internet + havalandırma + OS satırını yapıştır | Hedef teknik bilgi sıfır |
| 12 | Test scope | Taslak: OS detect, system info, GPU detect, network sanity, storage bench, AI smoke, power/thermal | Yeni session'da kesin onay alınacak |

**Yapılan işler:**
- `projects/tirekicker/` oluşturuldu, `README.md` yazıldı
- `repos/tirekicker/` oluşturuldu, `git init -b main` yapıldı
- `CLAUDE.md` (bootstrap context, kararlar, tasarım kuralları, planlanan yapı) yazıldı
- `memory.md` (bu dosya) yazıldı

**Henüz yapılmadı (yeni session konuları):**
1. GitHub repo'su oluşturulup remote bağlanacak (kullanıcı kendisi açıyor, paralel)
2. Test scope'u kesin onaylanacak (7 adım taslağı yeterli mi)
3. n8n webhook URL'i alınacak + secret yönetimi netleşecek
4. Short URL kurulumu (`tk.c3t.com.tr` CF Worker veya raw GH redirect)
5. JSON şeması (webhook'a giden payload formatı)
6. `run.sh` v0 implementasyonu
7. `lib/` modülleri
8. Test cihazı: kullanıcının lokal bir Linux + bir Mac üzerinde dry-run

### 2026-04-30 — Session 002 (test scope kilitleme)

**Bağlam:** İlk hedef cihaz **ASUS Ascent GX10** (NVIDIA GB10 Superchip, ARM aarch64, 128 GB unified memory, NVLink-C2C, ~2K USD). Cihaz değeri yüksek olduğundan tarama maksimum sinyalle yapılacak.

**Alınan kararlar:**

| # | Konu | Karar | Gerekçe |
|---|---|---|---|
| 13 | Sudo politikası | **%100 zorunlu** | 2K USD cihaz; SMART / dmidecode / serial / dmesg için tam veri lazım. Script başında `sudo -v` ile parola bir kez alınır, cache. CLAUDE.md "Tasarım Kuralları" madde 1 revize edildi. |
| 14 | Toplam test süresi | **~60 sn hedef** | Önceki "60–180 sn" üst sınırı 60'a çekildi. |
| 15 | OS kapsamı v0 | **Linux + Windows zorunlu** (run.sh + run.ps1 paralel). macOS v2'ye | Önceki "best effort" macOS v0 kapsamından çıkarıldı. |
| 16 | nvidia-smi yoksa | Devam + flag | Anomali raporlanır, diğer adımlar koşmaya devam eder. |
| 17 | JSON'da raw nvidia-smi -q vb. | **Dahil** | n8n parse zorlansa bile ham veri katma değer; başka ülkede de test edileceği için ileri yarar. |
| 18 | Spec doğrulaması | **n8n tarafında** | Script cihaz-agnostik kalsın; profile'lar n8n'de. Yarın Jetson eklerken script'e dokunmayacağız. |
| 19 | Final test scope | 11 adım (0–10) | Self-check, OS+arch, System (sudo dmidecode), Freshness, GPU+stack, AI smoke, Storage bench, NVMe SMART (sudo), Network, Thermal/Power (yüklü), Fingerprint + POST. |
| 20 | Thermal okuma zamanı | **Yük sonrası** | AI smoke + storage bench'ten sonra ~2 sn bekle, GPU/CPU temp + throttle reasons oku. Yüklü thermal yakalanır. |
| 21 | Speedtest | **Çıkarıldı** | Satıcı evi internet hızı bizi yanıltır; sadece link speed / duplex + public IP + up flag yeterli. |
| 22 | JSON şeması v0.1 | **Onaylı** | Ham bloklar düz string (gzip değil); fingerprint çift = 12-char + 64-char; `schema_version` 0.1; her modül parsed + raw; tüm hatalar tek `errors[]` listesinde. `lib/report.sh` referans alacak. |
| 23 | Delivery failover | **3 katman + ekran** | (1) n8n → (2) CF Worker (Telegram bot proxy) → (3) file upload (0x0.st → catbox → transfer.sh) + URL'yi Worker'a relay → (4) son çare: ekrana URL + JSON path. POST'un başarısız olması yasak. |
| 24 | Worker birleştirme + landing | **Onaylı** | `tk.c3t.com.tr/` HTML landing (EN/ES toggle, 2 buton, clipboard copy); `GET /win` (run.ps1 redirect); `POST /api/report` (n8n forward + Telegram); `POST /api/relay-url` (Tier 3 alarm). |
| 25 | Risk seviyesi | **Yüksek** | 4 cihaz × 2K = 8K USD borçla, iade yok, TR'de tamir yok, satıcı güvenilmez. Tarama saldırgan olacak. |
| 26 | Scope sıkılaştırma | **Onaylı (Session 002)** | 11→12 adım, ~60sn → ~85sn. Eklenen: (a) Hardware ID cross-check (NON-NEG madde 10), (b) sustained AI smoke 60s, (c) dmesg / journal hata pattern taraması, (d) retired pages + ECC aggregate, (e) NVLink-C2C + PCIe gen+lane, (f) RAM type+speed (`dmidecode -t memory`), (g) thermal 2 snapshot (yük sırası + yük sonrası), (h) storage bench AI smoke ile paralel. |
| 27 | 4 cihaz tipi | **Hepsi GX10** | Sustained AI smoke 60s GB10 thermal'i tetiklemek için. |
| 28 | Photo report | **README zorunlu** | 6 fotoğraf: ön / arka / alt / I-O paneli / adaptör etiketi / seri etiketi. Telegram'a script raporundan ayrı. |
| 29 | Two-pass UX | **README zorunlu** | "Done" sonrası arkadaş ödeme YAPMAZ; Telegram'dan "go ahead, pay" beklenir. EN + ES açıkça. |
| 30 | Worker rate-limit | IP başına **100 / dk** | 4 cihaz aynı anda test ederse rahat geçsin. |
| 31 | Repo + push | **Tamam** | `https://github.com/C3T-Teknoloji-AS/tirekicker` public, 4 commit, main upstream. |
| 32 | lib/ klasörü | **v0'da yok** | `run.sh` tek dosya, fonksiyonlar inline. `curl | bash` için en pürüzsüz. lib/ + build sistemi v1'e. |
| 33 | n8n iptal | **v0'da kapalı** | Kullanıcının n8n setup'ı düzgün çalışmıyor; açmakla uğraşılmıyor. CF Worker `handleReport`'ta n8n forward bloğu yorum satırı; `run.sh`'te Tier 1 (n8n direct) bloğu yorum satırı. Yeni delivery: (1) Worker → Telegram doğrudan, (2) file upload, (3) ekran. n8n eklenmek istenirse: yorum açılır + `N8N_WEBHOOK_URL` secret set edilir. |
| 34 | run.sh + Worker v0 yazıldı | **Tamam** | `run.sh` 12 adım tek dosya (~700 satır, fonksiyonlar inline, dry-run destekli). `deploy/cf-worker/index.js` multi-path (UA detect ile `/` curl/browser ayrımı; `/win`, `/run.sh`, `/api/report`, `/api/relay-url`); rate limit 100/dk per IP. `wrangler.toml` + deploy README hazır. |

## Açık Sorular

- **Sırlar (Adım 5b):** Telegram bot_token + chat_id — Worker deploy öncesi kullanıcıdan alınacak.
- **CF Worker route** (Adım 5e): `tk.c3t.com.tr` route ekleme — kullanıcı "deploy hazır" deyince.
- **Dry-run testi (Adım 5d):** Kullanıcının lokal Linux/Mac'inde `bash run.sh --dry-run` koşturulup ham JSON çıktısı incelenecek; Python/PyTorch yoksa AI smoke fallback'i nasıl davranıyor görülecek.

## Pattern Notları

- c3t convention: `projects/PROJE-ADI/README.md` meta info; gerçek kod `repos/REPO-ADI/`
- Commit dili: Türkçe
- Session sonu: `.wolf/memory.md` (ana c3t) güncellenir + bu dosya güncellenir
