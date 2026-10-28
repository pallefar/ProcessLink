# ProcessLink for Windows (Tauri 2)

The Windows form wraps the **same web bundle** as the Flightdeck sub-app, so
the privacy guard, scoring, savings ledger and page set are identical. This
folder holds only the shell.

## Status

Scaffolded, **not built on a Windows host** in this session (the build
machine is macOS). The config, Rust entry point and capabilities are complete;
run the commands below on Windows 11 to produce the installer.

## Build

Requirements: Windows 11, WebView2 (installed by default on 11), Node 20+,
Rust 1.77.2+ with the MSVC toolchain, and the Visual Studio Build Tools.

```powershell
cd ProcessLink\windows\ProcessLink.Windows
npm install
npm run dev      # development window
npm run build    # MSI + NSIS installer in src-tauri\target\release\bundle
```

The build runs `npm --prefix ../../../web run build` first, so the web form
must build (it does; 326 kB JS, 13 kB CSS gzipped to ~103 kB).

## Windows integrations

| Behaviour | How |
|---|---|
| One instance | `tauri-plugin-single-instance`; a second launch focuses the window. |
| `processlink://` links | Register the scheme in the installer (WiX/NSIS) and handle it in `single-instance`'s callback. This is a stub in the scaffold. |
| Sync notification | `tauri-plugin-notification` from the frontend after a sync with new opportunities. |
| Offline read | The last synced snapshot is cached in WebView2 local storage; drafts queue and replay when online. |
| Secrets | Windows Credential Manager (`keyring` crate) behind a Rust command. The web never receives the key. |
| File export | Brief downloads through the WebView; use `tauri-plugin-dialog` for a native Save dialog in the next pass. |

## Deliberately absent

- Screen capture, keystroke capture, Accessibility, or control of other
  applications. ProcessLink consumes KYP.ai; it does not capture work.
- Any credential in `localStorage` or in the repository.
- Autostart by default. Launch at login is a user choice, not an install
  side effect.

## Packaging notes

- The identifier is `com.te.processlink`, matching the macOS bundle id.
- The icon is generated from the macOS icon source; replace it with a proper
  Windows icon set (16–256 px, `.ico`) before signing.
- Code signing: an EV certificate is required for SmartScreen reputation.
  Unsigned MSI builds warn on first run; that is expected.
- Licence/IP: Tauri (MIT/Apache-2.0), WebView2 (Microsoft), React (MIT),
  Vite (MIT). No GPL/AGPL dependency is used.
