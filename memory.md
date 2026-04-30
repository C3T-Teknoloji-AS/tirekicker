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

## Açık Sorular

- Webhook URL'i build-time embed mi, runtime env mi? (Public repo + embed = URL ifşa olur. Ama URL kendisi secret değil; n8n tarafında basic-auth veya signed payload ile koruyabiliriz.)
- Sudo gereken adımlar (örn. `dmidecode` serial number için) opsiyonel mi yapılacak yoksa hiç istenmesin mi?
- GPU yoksa (CPU-only AI cihaz) AI smoke test ne yapsın? (Skip + raporla mı, CPU matmul mu)

## Pattern Notları

- c3t convention: `projects/PROJE-ADI/README.md` meta info; gerçek kod `repos/REPO-ADI/`
- Commit dili: Türkçe
- Session sonu: `.wolf/memory.md` (ana c3t) güncellenir + bu dosya güncellenir
