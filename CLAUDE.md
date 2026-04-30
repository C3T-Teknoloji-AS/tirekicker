# tirekicker — Claude Code Talimatlari

## Proje Ozeti

Yurtdışından 2.el AI cihazları (ASUS Ascent GX10, NVIDIA Jetson, EGX kit, Apple M-series Mac Studio, Windows AI PC vb.) **almadan önce** satıcının yanındaki **teknik olmayan** bir arkadaşımıza tek satır komut çalıştırtıp cihazın sağlığını uzaktan teşhis edeceğimiz script.

## İlk hedef cihaz — ASUS Ascent GX10

| Boyut | Değer |
|---|---|
| Mimari | **ARM aarch64** (NVIDIA GB10 Superchip — Grace-class CPU + Blackwell GPU tek pakette) |
| Bellek | **128 GB LPDDR5X unified** (CPU+GPU paylaşımlı) |
| Bağlantı | NVLink-C2C (CPU↔GPU dahili 600+ GB/s) |
| Stack beklentisi | NVIDIA driver ≥570, CUDA ≥12.6, cuDNN, muhtemelen PyTorch preinstalled (DGX-OS / Ubuntu 24.04) |
| Depolama | NVMe ~3.5–4 TB |
| Ağ | 10/5 GbE + Wi-Fi 7 |
| Güç | DC adapter ~150 W+, **batarya yok** |
| Form faktör | Mini-PC; termal throttle riski yüksek |

Cihaz değeri ~2K USD. Tarama maksimum sinyalle yapılır; sudo zorunludur.

## Akış

```
Satıcı yanındaki kişi
  → Linux  : curl -fsSL https://tk.c3t.com.tr | bash
    Windows: irm https://tk.c3t.com.tr/win | iex   (PowerShell, Run as Administrator)
  → script çalışır, ekrana adım adım İngilizce progress yazar
      [1/10] Detecting OS... ✓
      [2/10] Reading hardware info... ✓
      ...
  → tüm sonuçlar JSON olarak n8n webhook'a POST edilir
  → n8n bizi (Telegram) haberdar eder
  → biz "al / alma" kararını veririz
```

## Anlaşılan Kararlar (Session 001 + 002)

| Konu | Karar |
|---|---|
| Repo adı | `tirekicker` |
| GitHub org | `C3T-Teknoloji-AS` (kullanıcı reposu manuel oluşturuyor) |
| Görünürlük | **Public** (one-liner curl için) |
| Sonuç kanalı | **n8n webhook** → Telegram |
| Çıktı dili | Script ekran çıktısı **EN**. README **EN + ES**. İlk hedef ülke İspanya. Dahili docs (CLAUDE.md, memory.md, commit) **TR**. |
| OS kapsamı (v0) | **Linux + Windows zorunlu** (run.sh + run.ps1 paralel geliştirilecek). macOS v2'ye bırakıldı. İlk cihaz GX10 (Linux/aarch64). |
| Hedef süre | Kullanıcıya **5–10 dk** söylenir (güvenli pay). Gerçek çalışma **~60 sn hedef**. |
| Sudo | **Zorunlu**. Script başında `sudo -v` ile parola bir kez alınır, cache'lenir. README'de "you'll be asked for the device password once" notu olur. |
| Kullanıcı talimatı | Cihaz açık + internet + havalandırma + OS satırını yapıştır + sudo şifresi sorulduğunda gir + "Done" deyince kapat. |

## Tasarım Kuralları (NON-NEGOTIABLE)

1. **Tek satır komut + bir kez sudo parolası.** Linux için `curl ... | bash`, Windows için Run-as-Admin PowerShell + `irm | iex`. Başka manuel adım yok.
2. **Hiçbir kalıcı değişiklik yapılmaz.** Cihaza kurulum, paket indirme, dosya bırakma yok. Var olan araçları kullan; yoksa "missing" diye raporla.
3. **Hızlı.** Gerçek çalışma ~60 sn hedef. Kullanıcıya 5–10 dk söyleniyor (güvenli pay).
4. **Sessiz hata yok.** Bir adım fail olursa progress'te `✗ failed (sebep)` yazılır, script devam eder, JSON'da o alan `null` + ortak `errors[]` listesine kayıt düşer.
5. **Privacy.** SSH key, browser history, kullanıcı dosyaları **kesinlikle okunmaz**. Ham serial/MAC/UUID değil **hash** gönderilir.
6. **Self-contained.** Script tek dosya, external dependency'siz çalışmalı. `jq`, `python3`, `nvidia-smi`, `nvme-cli`, `dmidecode` varsa kullan; yoksa fallback / "missing" flag.
7. **Idempotent.** Aynı cihazda 5 kere çalıştırılırsa 5 tutarlı sonuç vermeli (timestamp ve random `report_id` hariç).
8. **Cihaz-agnostik.** Script "GX10 expected: ..." gibi profil tutmaz. Ham veri gönderir; beklenti karşılaştırması n8n tarafında yapılır. (Yarın Jetson eklerken script'e dokunmayacağız.)
9. **POST asla başarısız olamaz.** 3 katman + ekran fallback'lı delivery zinciri vardır: (1) n8n primary → (2) CF Worker (Telegram bot proxy, n8n bypass'ı) → (3) file upload (0x0.st → catbox → transfer.sh sırayla) → URL'yi Worker'a relay → (4) son çare: ekrana URL + JSON path. Satıcı yanındaki kişi "manuel gönder" gibi bir iş yapmaz.

## Test Scope (Onaylandı — Session 002)

Toplam 11 adım, ~60 sn bütçe. Sıralama, **thermal'i yüklü cihazda** okumak için bilinçli kuruldu (AI smoke + storage bench → sonra thermal).

| # | Adım | Bütçe | Ne ölçüyor |
|---|---|---|---|
| 0 | Self-check | ~1 s | bash version, curl, jq?, python3?, nvidia-smi?, nvme-cli?, dmidecode?, sudo cache |
| 1 | OS + arch | ~1 s | `uname -a`, `/etc/os-release`, mimari (aarch64 doğrula) |
| 2 | System info | ~3 s | CPU model+core, RAM byte, disk topology, **mb model+serial via `dmidecode` (sudo)** |
| 3 | Freshness / tamper | ~2 s | uptime, OS install date, journal hacmi (24h), package count, last-login count |
| 4 | GPU + stack | ~3 s | `nvidia-smi -q`, driver, CUDA, cuDNN, PyTorch version, NVLink topo |
| 5 | AI smoke | ~12 s | PyTorch fp16 matmul (4096 + 8192) → peak GFLOPS + memory used; numpy fallback |
| 6 | Storage bench | ~10 s | dd 5 sn write + 5 sn read (read+write MB/s) |
| 7 | NVMe SMART | ~1 s | `nvme smart-log` (sudo): power_on_hours, percentage_used, media_errors, temp |
| 8 | Network | ~3 s | link speed/duplex, public IP, internet up |
| 9 | Thermal / Power | ~3 s | (yük sonrası ~2 s bekle) GPU/CPU temp, power draw, **throttle reasons** |
| 10 | Fingerprint + POST | ~2 s | MAC + CPU + NVMe serial → SHA256, JSON birleştir, webhook POST |

**Çıkarılanlar (önceki taslaktan):**
- Internet speedtest (satıcı evi internet hızı bizi yanıltır)
- DNS / latency micro-test (POST başarısı zaten kanıtlar)
- Battery state (desktop AI cihazlarda anlamsız — yine de varsa raporlanır)

## Klasör Yapısı (planlanan)

```
tirekicker/
├── CLAUDE.md              → Bu dosya
├── memory.md              → Session log + kararlar
├── README.md              → GitHub'da görünen, satıcı yanındaki kişiye talimat
├── .gitignore
├── run.sh                 → Linux one-liner (curl | bash hedefi)
├── run.ps1                → Windows PowerShell (irm | iex hedefi, admin)
├── lib/
│   ├── self-check.sh
│   ├── detect-os.sh
│   ├── system-info.sh
│   ├── freshness.sh
│   ├── gpu-stack.sh
│   ├── ai-smoke.sh
│   ├── storage-bench.sh
│   ├── nvme-smart.sh
│   ├── network.sh
│   ├── thermal.sh
│   ├── fingerprint.sh
│   ├── delivery.sh        → 3-tier POST failover (n8n → Worker → file upload → ekran)
│   └── report.sh          → JSON birleştir, delivery.sh'i çağırır
└── deploy/
    └── shorturl-setup.md  → tk.c3t.com.tr CF Worker / redirect kurulumu
```

## Bekleyen Konular

- [x] **Adım 2** — JSON payload şeması v0.1 onaylı (Session 002)
- [ ] **Adım 3 + 4 (birleşik öneri)** — `tk.c3t.com.tr` üstünde tek CF Worker, multi-path: `GET /` (run.sh redirect), `GET /win` (run.ps1 redirect), `POST /api/report` (n8n forward + Telegram), `POST /api/relay-url` (Tier 3 alarm). 3 katmanlı delivery failover. Kullanıcı onayı + sırlar (n8n URL, Telegram bot_token, chat_id) bekleniyor.
- [ ] **Adım 5** — GitHub remote bağla + ilk push (kullanıcı `C3T-Teknoloji-AS/tirekicker` repo'sunu açacak)
- [ ] `run.sh` v0 + `lib/*` modülleri (önce kullanıcının lokal Linux'unda dry-run)
- [ ] `run.ps1` v0 (Linux'tan sonra, Windows AI PC dry-run)
- [ ] CF Worker kodu (`deploy/cf-worker/index.js`) + n8n flow tasarımı
- [ ] README'de Linux/Windows talimatı; macOS satırı v0'da kapatılır

## Çalışma Tarzı

- README **EN + ES iki dilli + çok yalın** (kopyala-yapıştır + sudo şifresi + Done = kapat). Teknik ayrıntı sıfır.
- Script ekran çıktısı **EN**.
- CLAUDE.md, memory.md, commit'ler **TR**.
- Commitler Türkçe, c3t standardı.
- Her session sonunda memory.md güncellenir (Session NNN bloğu + Açık Sorular revize).
- OpenWolf protokolü: ana c3t/CLAUDE.md kuralları (proje arama sırası `projects/` öncelikli, sudo onay vb.) hâlâ bağlayıcı.
