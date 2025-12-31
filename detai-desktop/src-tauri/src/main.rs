// Prevents additional console window on Windows in release
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod capture;
mod plugin;
mod server;
mod speech;

use tauri::{
    CustomMenuItem, Manager, SystemTray, SystemTrayEvent, SystemTrayMenu, SystemTrayMenuItem,
};
use tracing::{info, error};
use tracing_subscriber;

fn main() {
    // Initialize logging
    tracing_subscriber::fmt::init();

    // Build system tray menu
    let quit = CustomMenuItem::new("quit".to_string(), "Quit DetAI");
    let status = CustomMenuItem::new("status".to_string(), "Status: Starting...").disabled();
    let reinstall = CustomMenuItem::new("reinstall".to_string(), "Reinstall Plugin");
    let check_update = CustomMenuItem::new("check_update".to_string(), "Check for Updates");
    let open_plugins = CustomMenuItem::new("open_plugins".to_string(), "Open Plugins Folder");

    let tray_menu = SystemTrayMenu::new()
        .add_item(status)
        .add_native_item(SystemTrayMenuItem::Separator)
        .add_item(reinstall)
        .add_item(open_plugins)
        .add_native_item(SystemTrayMenuItem::Separator)
        .add_item(check_update)
        .add_native_item(SystemTrayMenuItem::Separator)
        .add_item(quit);

    let system_tray = SystemTray::new().with_menu(tray_menu);

    tauri::Builder::default()
        .system_tray(system_tray)
        .on_system_tray_event(|app, event| match event {
            SystemTrayEvent::MenuItemClick { id, .. } => {
                match id.as_str() {
                    "quit" => {
                        info!("Quit requested");
                        std::process::exit(0);
                    }
                    "reinstall" => {
                        info!("Reinstall plugin requested");
                        match plugin::install_plugin() {
                            Ok(_) => {
                                let _ = tauri::api::notification::Notification::new(&app.config().tauri.bundle.identifier)
                                    .title("DetAI")
                                    .body("Plugin reinstalled successfully! Restart Roblox Studio to use it.")
                                    .show();
                            }
                            Err(e) => {
                                error!("Failed to reinstall plugin: {}", e);
                                let _ = tauri::api::notification::Notification::new(&app.config().tauri.bundle.identifier)
                                    .title("DetAI Error")
                                    .body(&format!("Failed to reinstall plugin: {}", e))
                                    .show();
                            }
                        }
                    }
                    "open_plugins" => {
                        if let Some(home) = dirs::home_dir() {
                            let plugins_path = home.join("Documents/Roblox/Plugins");
                            let _ = std::process::Command::new("open")
                                .arg(plugins_path)
                                .spawn();
                        }
                    }
                    "check_update" => {
                        info!("Check for updates requested");
                        // Tauri updater handles this automatically
                        app.trigger_global("tauri://update", None);
                    }
                    _ => {}
                }
            }
            _ => {}
        })
        .setup(|app| {
            info!("DetAI Desktop starting up...");

            // Install plugin on first run
            match plugin::install_plugin() {
                Ok(installed) => {
                    if installed {
                        info!("Plugin installed successfully");
                        let _ = tauri::api::notification::Notification::new(&app.config().tauri.bundle.identifier)
                            .title("DetAI")
                            .body("Plugin installed! Open Roblox Studio to use DetAI.")
                            .show();
                    } else {
                        info!("Plugin already installed");
                    }
                }
                Err(e) => {
                    error!("Failed to install plugin: {}", e);
                }
            }

            // Start HTTP server for screenshot capture
            let handle = app.handle();
            tauri::async_runtime::spawn(async move {
                if let Err(e) = server::start_capture_server(handle).await {
                    error!("Failed to start capture server: {}", e);
                }
            });

            // Update tray status
            let tray_handle = app.tray_handle();
            let _ = tray_handle.get_item("status").set_title("Status: Running (port 4850)");

            info!("DetAI Desktop ready");
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
