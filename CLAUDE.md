# tirekicker — Claude Code Talimatlari

## Proje Ozeti

Yurtdışından 2.el AI cihazları (ASUS Ascent GX10, NVIDIA Jetson, EGX kit, Apple M-series Mac Studio, Windows AI PC vb.) **almadan önce** satıcının yanındaki **teknik olmayan** bir arkadaşımıza tek satır komut çalıştırtıp cihazın sağlığını uzaktan teşhis edeceğimiz script.

## Akış

```
Satıcı yanındaki kişi
  → tek komut: curl -fsSL https://tk.c3t.com.tr | bash
  → script çalışır, ekrana adım adım İngilizce progress yazar:
      [1/7] Detecting OS... ✓
      [2/7] Reading hardware info... ✓
      [3/7] Checking GPU... ✓
      ...
  → tüm sonuçlar JSON olarak n8n webhook'a POST edilir
  → n8n bizi (Telegram) haberdar eder
  → biz "al / alma" kararını veririz
```

## Anlaşılan Kararlar (2026-04-30)

| Konu | Karar |
|---|---|
| Repo adı | `tirekicker` |
| GitHub org | `C3T-Teknoloji-AS` (kullanıcı reposu manuel oluşturuyor) |
| Görünürlük | **Public** (one-liner curl için private = token zorunluluğu, satıcı arkadaşa yük olur) |
| Sonuç kanalı | **n8n webhook** → Telegram (URL henüz set edilmedi, secret olarak yönetilecek) |
| Çıktı dili | Script ekran çıktısı **İngilizce** (hedef kullanıcı yabancı). Dokümantasyon Türkçe. |
| OS desteği | Linux (~%90, öncelik), Windows (~%10), macOS (Apple Silicon AI cihazlar için), olası diğer |
| Test scope | Henüz kesin değil — yeni session başında konuşulacak. Ön taslak aşağıda. |

## Tasarım Kuralları (NON-NEGOTIABLE)

1. **Tek satır komut.** Satıcı yanındaki kişi 1 komut yazacak, başka bir şey yazmayacak. `sudo` istenmemeli (ya optional yapılır ya da elden geliyorsa olmadan çalışır).
2. **Hiçbir kalıcı değişiklik yapılmaz.** Cihaza kurulum, paket indirme, dosya bırakma yok. Tüm araçlar zaten kuruluysa kullan, değilse "missing" raporla.
3. **Hızlı.** Toplam çalışma 60–120 saniye arası hedef. Satıcı önünde uzun süre tutamayız.
4. **Sessiz hata yok.** Bir adım fail olursa progress'te "✗ failed (sebep)" yazılır, script devam eder, JSON'da `null` + `error` field'ı olur.
5. **Privacy.** SSH key, browser history, kullanıcı dosyaları KESINLIKLE okunmaz. Sadece donanım/sistem fingerprint'i.
6. **Self-contained.** Script tek dosya, external dependency'siz çalışmalı (jq vb. varsa kullan, yoksa pure bash/awk fallback).
7. **Idempotent.** Aynı cihazda 5 kere çalıştırılırsa 5 tutarlı sonuç vermeli.

## Önerilen Test Scope (taslak — onaylanacak)

Toplam ~7 adım, ~60-90sn:

1. **OS detect** — `uname -a`, `/etc/os-release`, `sw_vers`, Windows için `systeminfo`
2. **System info** — CPU model/cekirdek, RAM toplam, disk capacity + free, model/serial
3. **GPU detect** — NVIDIA: `nvidia-smi`; Apple: `system_profiler SPDisplaysDataType`; Windows: `dxdiag`/`wmic path win32_VideoController`
4. **Network sanity** — public IP (geo doğrulama satıcı lokasyonu için), DNS ping, latency to 1.1.1.1
5. **Storage benchmark** — 5sn dd/fio mini test (read+write MB/s)
6. **AI smoke test** — Python varsa: küçük tensor matmul + GPU mem alloc (PyTorch yoksa numpy fallback). Yoksa `nvidia-smi` ile GPU memory utilization snapshot.
7. **Power/thermal** — CPU temp, GPU temp (varsa), AC/battery state

Her adım sonunda JSON'a obje eklenir, sonunda webhook'a tek POST atılır.

## Klasör Yapısı (planlanan)

```
tirekicker/
├── CLAUDE.md              → Bu dosya (claude için bootstrap)
├── memory.md              → Session log + kararlar
├── README.md              → GitHub'da görünen, satıcı yanındaki kişiye talimat
├── .gitignore
├── run.sh                 → Linux/macOS one-liner (curl | bash hedefi)
├── run.ps1                → Windows PowerShell muadili (faz 2)
├── lib/
│   ├── detect-os.sh
│   ├── system-info.sh
│   ├── gpu-detect.sh
│   ├── network.sh
│   ├── storage.sh
│   ├── ai-smoke.sh
│   └── report.sh          → JSON birleştir + webhook POST
└── deploy/
    └── shorturl-setup.md  → tk.c3t.com.tr CF Worker / redirect kurulumu
```

## Bekleyen Konular (yeni session açılışında)

- [ ] GitHub repo oluştu mu? Remote bağlanacak.
- [ ] n8n webhook URL'i — secret nasıl yönetilecek? (Build time embed mi, env mi, query param mi)
- [ ] Test scope kesin onayı (yukarıdaki 7 adım yeterli mi, fazla/eksik var mı)
- [ ] Short URL: `tk.c3t.com.tr` mi, başka mı? CF Worker mı raw.githubusercontent redirect mi?
- [ ] Script bitirme sonrası kullanıcıya ne gösterilecek? ("Done. Results sent. You may close this window.")
- [ ] Webhook'a giden JSON şeması net olmalı (n8n tarafında parse'ı kolaylaştırmak için)

## Çalışma Tarzı

- Bu repo c3t altında ama **kullanıcılar yurtdışındaki satıcılar** — README ve script çıktısı **İngilizce**. Geri kalan her şey (CLAUDE.md, memory.md, commitler) **Türkçe**.
- Commitler Türkçe, c3t standardı.
- OpenWolf protokolü geçerli — ana c3t/CLAUDE.md'deki kurallar (proje aramada `projects/` öncelikli, sudo onaysız çalışmaz vb.) hâlâ bağlayıcı.
