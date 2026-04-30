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
| 24 | Worker birleştirme önerisi | **Beklemede (Adım 3+4 birleşik)** | `tk.c3t.com.tr` üstünde tek CF Worker — `GET /` (run.sh redirect), `GET /win` (run.ps1), `POST /api/report`, `POST /api/relay-url`. Adım 3 ve 4'ü tek karara çevirir. Kullanıcı onayı bekleniyor. |

## Açık Sorular

- **Worker birleştirme** (Adım 3+4): tek Worker multi-path mi, ayrı subdomain mi?
- **Sırlar:** n8n URL + Telegram bot_token + chat_id'i kullanıcıdan ne zaman alacağız (şimdi mi, Adım 5 remote bağlamayla mı)?
- **CF account izni:** `tk.c3t.com.tr` Worker route ekleme zamanı (kullanıcı "hazır" diyince).

## Pattern Notları

- c3t convention: `projects/PROJE-ADI/README.md` meta info; gerçek kod `repos/REPO-ADI/`
- Commit dili: Türkçe
- Session sonu: `.wolf/memory.md` (ana c3t) güncellenir + bu dosya güncellenir
