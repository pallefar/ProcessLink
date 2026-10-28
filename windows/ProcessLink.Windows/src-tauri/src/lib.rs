//! ProcessLink for Windows.
//!
//! The UI is the same web bundle as the Flightdeck sub-app, so there is one
//! set of domain rules (privacy guard, scoring, savings ledger). What is
//! Windows-specific lives here, not in the frontend:
//!
//!   * a single instance, so `processlink://` links and second launches
//!     focus the window rather than opening a second copy;
//!   * desktop notifications after an incremental sync;
//!   * a normal window with the system title bar (no custom chrome);
//!   * offline read access through WebView2's local storage, populated by
//!     the last successful sync (the service worker is not used here).
//!
//! Deliberately NOT here: screen capture, Accessibility, window control of
//! other apps, or any credential persistence in the WebView. Secrets belong
//! in Windows Credential Manager, read by a Rust command that the frontend
//! calls but never sees the raw value of.

use tauri::Manager;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _argv, _cwd| {
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.show();
                let _ = window.unminimize();
                let _ = window.set_focus();
            }
        }))
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_opener::init())
        .setup(|_app| Ok(()))
        .run(tauri::generate_context!())
        .expect("error while running ProcessLink");
}
