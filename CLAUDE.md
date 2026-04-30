# tirekicker — Claude Code Talimatlari

## Proje Ozeti

Yurtdışından 2.el AI cihazları (ASUS Ascent GX10 vb.) **almadan önce** satıcının yanındaki **teknik olmayan** bir arkadaşımıza tek satır komut çalıştırtıp cihazın sağlığını uzaktan teşhis edeceğimiz script.

## Risk Bağlamı (Session 002 — kritik)

- **4 adet ASUS Ascent GX10**, cihaz başı ~2K USD = **toplam 8K USD**
- İspanya'da **güvenilmez** 2.el dükkanından alınacak
- **Borçla** alınıyor; **iade yok**, **TR'de tamir şansı yok**, bavula koyup gelecek
- Çöp çıkarsa kullanıcı için ciddi finansal zarar

→ Tarama saldırgan ve **dolandırıcı-yakalama** odaklı. Sadece donanım envanteri değil; spoofing, refurbished, swap, tamper, throttle gizleme gibi vektörlere kanıt arıyoruz.

## İlk hedef cihaz — ASUS Ascent GX10 (×4)

| Boyut | Değer |
|---|---|
| Mimari | **ARM aarch64** (NVIDIA GB10 Superchip — Grace-class CPU + Blackwell GPU tek pakette) |
| Bellek | **128 GB LPDDR5X unified** (CPU+GPU paylaşımlı) |
| Bağlantı | NVLink-C2C (CPU↔GPU 600+ GB/s dahili) |
| Stack beklentisi | NVIDIA driver ≥570, CUDA ≥12.6, cuDNN, muhtemelen PyTorch preinstalled (DGX-OS / Ubuntu 24.04) |
| Depolama | NVMe ~3.5–4 TB |
| Ağ | 10/5 GbE + Wi-Fi 7 |
| Güç | DC adapter ~150 W+, batarya yok |
| Form faktör | Mini-PC; termal throttle riski yüksek |

## Akış

```
Satıcı yanındaki kişi
  → Linux  : curl -fsSL https://tk.c3t.com.tr | bash
    Windows: irm https://tk.c3t.com.tr/win | iex   (PowerShell, Run as Administrator)
  → script ~85 sn çalışır, ekrana adım adım İngilizce progress yazar
      [1/12] Detecting OS... ✓
      ...
      [7/12] Running sustained AI smoke (60s)... ✓
      ...
  → tüm sonuçlar JSON olarak n8n webhook'a POST edilir (3 katman failover)
  → n8n + Telegram bizi haberdar eder
  → biz "al / alma" kararını veririz
  → arkadaş Telegram'da "go ahead" gelene kadar ödeme YAPMAZ (two-pass UX)
```

## Anlaşılan Kararlar (Session 001 + 002)

| Konu | Karar |
|---|---|
| Repo adı | `tirekicker` |
| Repo URL | `https://github.com/C3T-Teknoloji-AS/tirekicker` (public) |
| GitHub org | `C3T-Teknoloji-AS` |
| Sonuç kanalı | n8n webhook → Telegram (3 katman failover; CF Worker proxy) |
| Çıktı dili | Script EN. README **EN + ES**. İlk hedef ülke İspanya. Dahili docs (CLAUDE.md, memory.md, commit) **TR**. |
| OS kapsamı (v0) | **Linux + Windows zorunlu**. macOS v2'ye. |
| Hedef süre | Kullanıcıya 5–10 dk. Gerçek çalışma **~85 sn** (sustained AI smoke 60 s). |
| Sudo | **Zorunlu**. Script başında `sudo -v` ile parola bir kez. |
| Test cihazı sayısı | **4 × GX10** (sustained smoke 60 s GB10 thermal'i tetiklemek için). |

## Tasarım Kuralları (NON-NEGOTIABLE)

1. **Tek satır komut + bir kez sudo parolası.** Linux için `curl ... | bash`, Windows için Run-as-Admin PowerShell + `irm | iex`. Başka manuel adım yok.
2. **Hiçbir kalıcı değişiklik yapılmaz.** Cihaza kurulum, paket indirme, dosya bırakma yok. Var olan araçları kullan; yoksa "missing" diye raporla.
3. **Hızlı.** Gerçek çalışma ~85 sn hedef. Kullanıcıya 5–10 dk söyleniyor (güvenli pay).
4. **Sessiz hata yok.** Bir adım fail olursa progress'te `✗ failed (sebep)` yazılır, script devam eder, JSON'da o alan `null` + ortak `errors[]` listesine kayıt düşer.
5. **Privacy.** SSH key, browser history, kullanıcı dosyaları **kesinlikle okunmaz**. Ham serial/MAC/UUID değil **hash** gönderilir.
6. **Self-contained.** Script tek dosya, external dependency'siz. `jq`, `python3`, `nvidia-smi`, `nvme-cli`, `dmidecode`, `lspci` varsa kullan; yoksa fallback / "missing" flag.
7. **Idempotent.** Aynı cihazda 5 kere çalıştırılırsa 5 tutarlı sonuç vermeli (timestamp ve random `report_id` hariç).
8. **Cihaz-agnostik.** Script "GX10 expected: ..." gibi profil tutmaz. Ham veri gönderir; beklenti karşılaştırması n8n tarafında yapılır.
9. **POST asla başarısız olamaz.** 3 katman + ekran fallback'lı delivery zinciri: (1) n8n primary → (2) CF Worker (Telegram bot proxy) → (3) file upload (0x0.st → catbox → transfer.sh) → URL'yi Worker'a relay → (4) son çare: ekrana URL + JSON path. Satıcı yanındaki kişi "manuel gönder" gibi bir iş yapmaz.
10. **Hardware ID cross-check.** GPU adı (`nvidia-smi`) + PCI Device ID (`lspci -vnn`) + board serial (`dmidecode -t baseboard`) **tutarlı olmak zorunda**. Tutarsızlık → JSON'da `hwid_mismatch: true` flag'i.

## Test Scope (Sıkılaştırılmış — Session 002)

12 adım, ~85 sn bütçe. Sıralama, **thermal'i yüklü cihazda** okumak için bilinçli kuruldu.

| # | Adım | Bütçe | Ne ölçüyor |
|---|---|---|---|
| 0 | Self-check | ~1 s | bash version, jq, python3, nvidia-smi, nvme, dmidecode, lspci varlığı; sudo cache |
| 1 | OS + arch | ~1 s | `uname -a`, `/etc/os-release`, mimari (aarch64 doğrula) |
| 2 | System info | ~3 s | CPU model+core, RAM byte + **type+speed** (`dmidecode -t memory`), disk topology, board serial |
| 3 | **Hardware ID cross-check** | ~2 s | `nvidia-smi` GPU adı vs `lspci -vnn` PCI Device ID vs `dmidecode` board — tutarlılık |
| 4 | Freshness / tamper | ~3 s | uptime, OS install date, journal hacmi (24h), package count, last-login count |
| 5 | GPU + stack + topology | ~3 s | `nvidia-smi -q`, driver, CUDA, cuDNN, PyTorch, **NVLink-C2C link**, **PCIe gen+lane**, **retired pages**, **ECC aggregate** |
| 6 | **dmesg history scan** | ~2 s | `dmesg -T` + `journalctl -p err --since 24h` — pattern: "MCE", "machine check", "PCIe error", "GPU has fallen off the bus", "fail" — count + sample |
| 7 | **AI smoke sustained 60 s** | ~60 s | PyTorch fp16 matmul büyük tensor (~80 GB unified) sürekli yük → peak GFLOPS, throttle behavior, memory bandwidth |
| 8 | Storage bench | (paralel #7'nin son 5 s'i) | dd 5 sn write + 5 sn read |
| 9 | NVMe SMART | ~1 s | `nvme smart-log` (sudo): power_on_hours, percentage_used, media_errors, temp |
| 10 | Network | ~3 s | link speed/duplex, public IP, internet up |
| 11 | **Thermal/Power 2 snapshot** | ~3 s | (a) #7 yük sırası — 1× snapshot; (b) yük sonrası ~2 s sonra — 1× snapshot. GPU/CPU temp, power draw, throttle reasons |
| 12 | Fingerprint + POST | ~2 s | MAC + CPU + NVMe + board serial → SHA256 (12-char + 64-char), JSON birleştir, delivery zinciri |

**Toplam:** ~85 sn. Kullanıcıya 5–10 dk söyleniyor — bol pay.

**Çıkarılanlar:** internet speedtest, DNS micro-test, battery state.

## Klasör Yapısı

```
tirekicker/
├── CLAUDE.md
├── memory.md
├── README.md
├── .gitignore
├── run.sh              → tek dosya bash (curl | bash hedefi, fonksiyonlar inline)
├── run.ps1             → tek dosya PowerShell (Windows, irm | iex hedefi)
└── deploy/
    └── cf-worker/
        ├── index.js    → Worker source (multi-path: /, /win, /api/report, /api/relay-url)
        ├── wrangler.toml
        └── README.md   → deploy adımları
```

(`lib/` klasörü v1'e bırakıldı — v0'da modüller `run.sh` içinde fonksiyonlar olarak. Build sistemi gereksiz karmaşıklık. `curl | bash` tek dosyada en pürüzsüz.)

## Photo Report (README'de zorunlu)

Script donanım kimliğini görür, fiziksel hasarı görmez. Satıcı yanındaki arkadaş **6 fotoğraf** çekip Telegram'a yollar:

1. Cihaz **önden**
2. Cihaz **arkadan**
3. Cihaz **alttan** (etiket varsa)
4. **I/O paneli** yakın çekim (port hasarı?)
5. **Adaptör etiketi** — wattaj okunacak şekilde
6. Cihaz **seri etiketi** (varsa, açık net)

Bu fotoğraflar script raporundan **ayrı** Telegram'a düşer; biz n8n + foto + cross-check ile karar veririz.

## Two-Pass UX (README'de zorunlu)

Script **"Done"** dediğinde arkadaş **henüz ödeme yapmaz**. Bizim Telegram'dan **"go ahead, pay"** mesajımızı bekler. Aksi halde rapor bize gelir ama tezgâh çoktan kapanmıştır.

README'de EN + ES açıkça yazılır. Arkadaşa cihaz başına ortalama 5 dk bekleme süresi söylenir.

## Bekleyen Konular

- [x] **Adım 1** — Test scope kilitlendi + sıkılaştırıldı (Session 002)
- [x] **Adım 2** — JSON şeması v0.1
- [x] **Adım 3 + 4** — Tek CF Worker multi-path, `tk.c3t.com.tr`
- [x] **Adım 5a** — Repo açıldı, remote bağlandı, ilk push
- [ ] **Adım 5b** — Sırlar: n8n URL + Telegram bot_token + chat_id (Worker secrets'a)
- [ ] **Adım 5c** — `run.sh` v0 + `deploy/cf-worker/index.js` iskeleti
- [ ] **Adım 5d** — Lokal Mac/Linux dry-run, output incele, düzeltmeler
- [ ] **Adım 5e** — Worker deploy + `tk.c3t.com.tr` route bind
- [ ] **Adım 5f** — Senin yanında GX10 yok — alternatif: dummy run + Telegram doğrulaması
- [ ] **Adım 5g** — `run.ps1` (Windows)
- [ ] İspanya'ya yollanır

## Çalışma Tarzı

- README **EN + ES iki dilli + çok yalın** (kopyala-yapıştır + sudo şifresi + Done = tezgâhta bekle).
- Script ekran çıktısı **EN**.
- CLAUDE.md, memory.md, commit'ler **TR (ASCII)** — c3t convention.
- Her session sonu memory.md güncellenir (Session NNN bloğu + Açık Sorular revize).
- OpenWolf protokolü: ana c3t/CLAUDE.md kuralları (proje arama sırası, sudo onay vb.) hâlâ bağlayıcı.
