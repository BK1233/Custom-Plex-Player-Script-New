# Custom Plex Player Configuration for Windows 11
## NVIDIA RTX Video Super Resolution (VSR) & RTX HDR Support

This repository provides an automated, dynamic solution to turn your standard **Plex HTPC** and **Plex for Windows** players into high-fidelity custom video renderers leveraging NVIDIA's advanced hardware capabilities:
1. **NVIDIA RTX Video Super Resolution (VSR)**: AI-enhanced video upscaling dynamically calculated matching your exact video-to-display resolution ratio.
2. **NVIDIA RTX Video HDR**: Sophisticated real-time SDR-to-HDR upconversion for standard dynamic range content, rendering deep contrast and color on HDR10 / Windows 11 HDR displays.

---

### 🚀 Quick Run (No Clone / Download Required)

To configure your Plex players instantly without downloading or cloning this repository, simply open **PowerShell as Administrator** and copy/paste the following command:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12; Invoke-Expression (Invoke-RestMethod -Uri "https://raw.githubusercontent.com/anthonybaldwin/Custom-Plex-Player-Script-New/main/Configure-RTX-Plex.ps1" -UseBasicParsing)
```

*(Note: If you are running a custom branch, you can replace `/main/` in the URL with your branch name.)*

---

### Features & Dynamic Automation

- **`autovsr_rtxhdr.lua`**:
  - Automatically identifies whether your currently playing media is SDR or Native HDR to prevent overriding native content metadata.
  - Dynamically calculates the optimal upscaling ratio for RTX VSR.
  - Performs on-the-fly format adjustments (such as mapping 10-bit HEVC `p10le`/`p010` inputs to `nv12`) for maximum NVIDIA hardware compatibility.
  - Switches colorspaces (`x2bgr10` output) dynamically when SDR-to-HDR processing is engaged.
  - Provides instant keyboard hotkey bindings:
    - `Ctrl+Shift+R` - Toggle NVIDIA VSR (On / Off)
    - `Ctrl+Shift+H` - Toggle RTX HDR SDR-to-HDR (On / Off)
    - `Ctrl+Shift+S` - Show detailed, real-time OSD overlay showing current active filters, scaling factor, colorspaces, decoders, and playback engines.

- **`Configure-RTX-Plex.ps1`**:
  - Elevates to Administrator, verifies active NVIDIA GPU hardware presence, and Windows HDR state.
  - Scans for default installations of both **Plex HTPC** and **Plex for Windows**.
  - Backs up existing player DLLs and automatically installs/upgrades the player's core playback engine (`libmpv-2.dll`) to the latest compatible modern release (compiled by `mitzsch/mpv-winbuild` with `d3d11vpp` and `nvidia-true-hdr` filter flags).
  - Automatically provisions the custom `%LocalAppData%\Plex` and `%LocalAppData%\Plex HTPC` configurations, creating/merging optimized `mpv.conf` rendering parameters (`gpu-context=d3d11`, `vo=gpu-next`, `hwdec=d3d11va`, and `temporal-dither`).
  - Installs the Lua script directly into the respective scripts folders.

---

### Prerequisites & Requirements

1. **Hardware**: NVIDIA RTX GPU (RTX 20, 30, 40, or 50 series or newer).
2. **Operating System**: Windows 11.
3. **Display**: HDR-capable monitor with **HDR turned ON** in Windows Settings (required for RTX HDR SDR-to-HDR upconversion).
4. **NVIDIA Settings**:
   - Open the **NVIDIA App** or **NVIDIA Control Panel**.
   - Navigate to **Video -> Adjust video image settings**.
   - Under **RTX Video Enhancement**:
     - Toggle/Check **Super Resolution** (Quality Auto or 1-4).
     - Toggle/Check **High Dynamic Range** (RTX Video HDR).

---

### Manual Installation

If you prefer to download the files and run them manually:

1. Open a PowerShell prompt with **Administrator privileges** (Right-click -> Run as Administrator).
2. Clone this repository or download the files.
3. Navigate to the repository directory and execute the setup utility:
   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process -Force
   .\Configure-RTX-Plex.ps1
   ```
4. Start your **Plex HTPC** or **Plex for Windows** player, play any standard content, and enjoy the AI-powered upscaling and HDR expansion!
