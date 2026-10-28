use tauri::Manager;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        // A second launch focuses the existing window instead of opening a
        // second copy against the same local store.
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.unminimize();
                let _ = window.set_focus();
            }
        }))
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_notification::init())
        .run(tauri::generate_context!())
        .expect("error while running ProcessLink");
}
