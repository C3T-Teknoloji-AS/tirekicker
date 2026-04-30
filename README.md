# tirekicker

> Pre-purchase remote diagnostic for AI hardware. One command, one minute, zero install.

When you're about to buy a second-hand AI device (NVIDIA dev kits, ASUS Ascent GX10, Jetson, Apple M-series, Windows AI PCs, etc.) and the person standing in front of the seller is **not technical**, run this:

## Linux / macOS

```bash
curl -fsSL https://tk.c3t.com.tr | bash
```

## Windows (PowerShell, run as user)

```powershell
irm https://tk.c3t.com.tr/win | iex
```

That's it. The script will:

1. Print step-by-step progress in English
2. Collect hardware info (CPU, GPU, RAM, disk, OS)
3. Run a brief AI smoke test
4. POST a JSON report to our team
5. Tell you when it's done

**No installation. No system changes. No private data. ~60–120 seconds.**

---

## What this collects

- OS and version, machine model
- CPU model & cores, RAM total, disk capacity & free space
- GPU model, driver version, memory
- Public IP (location only) and basic network latency
- Short storage read/write benchmark
- Quick AI workload smoke test (when GPU is present)
- Temperature / power state

## What this does NOT collect

- No browser history, no SSH keys, no user files
- No installed application list, no personal data
- No login credentials of any kind

## Repo structure

Implementation is in progress. See `CLAUDE.md` for design decisions and `memory.md` for session log.
