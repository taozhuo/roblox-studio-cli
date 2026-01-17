// Prevents additional console window on Windows in release
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod capture;
mod plugin;
mod server;
mod speech;

use tauri::{
    CustomMenuItem, Manager, SystemTray, SystemTrayEvent, SystemTrayMenu, SystemTrayMenuItem,
    Window, PhysicalPosition, PhysicalSize, AppHandle,
};
use tracing::{info, error};
use tracing_subscriber;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

// Swift FFI for window bounds (fast!)
#[cfg(target_os = "macos")]
extern "C" {
    fn get_roblox_studio_window_bounds(
        out_x: *mut i32,
        out_y: *mut i32,
        out_w: *mut i32,
        out_h: *mut i32,
    ) -> bool;
}

static SNAP_ENABLED: AtomicBool = AtomicBool::new(false);

/// Get Roblox Studio window bounds via Swift FFI (fast!)
#[cfg(target_os = "macos")]
fn get_studio_window_bounds() -> Option<(i32, i32, i32, i32)> {
    let mut x: i32 = 0;
    let mut y: i32 = 0;
    let mut w: i32 = 0;
    let mut h: i32 = 0;

    let found = unsafe {
        get_roblox_studio_window_bounds(&mut x, &mut y, &mut w, &mut h)
    };

    if found {
        Some((x, y, w, h))
    } else {
        None
    }
}

#[cfg(not(target_os = "macos"))]
fn get_studio_window_bounds() -> Option<(i32, i32, i32, i32)> {
    None
}

/// Position window to the right of Studio
fn position_next_to_studio(window: &Window) -> Result<(), String> {
    let bounds = get_studio_window_bounds()
        .ok_or_else(|| "Roblox Studio not found".to_string())?;

    let (studio_x, studio_y, studio_w, studio_h) = bounds;

    let detai_width = 420;
    let detai_x = studio_x + studio_w;
    let detai_y = studio_y;
    let detai_h = studio_h;

    window.set_position(PhysicalPosition::new(detai_x, detai_y))
        .map_err(|e| e.to_string())?;
    window.set_size(PhysicalSize::new(detai_width, detai_h as u32))
        .map_err(|e| e.to_string())?;

    Ok(())
}

#[tauri::command]
async fn snap_to_studio(window: Window) -> Result<String, String> {
    // Toggle snap mode
    let was_enabled = SNAP_ENABLED.load(Ordering::SeqCst);
    let now_enabled = !was_enabled;
    SNAP_ENABLED.store(now_enabled, Ordering::SeqCst);

    if now_enabled {
        info!("Snap to Studio enabled");
        position_next_to_studio(&window)?;
        Ok("Snap enabled - window will follow Studio".to_string())
    } else {
        info!("Snap to Studio disabled");
        Ok("Snap disabled".to_string())
    }
}

#[tauri::command]
async fn get_snap_status() -> bool {
    SNAP_ENABLED.load(Ordering::SeqCst)
}

/// Start background task to keep window snapped to Studio
fn start_snap_monitor(handle: AppHandle) {
    tauri::async_runtime::spawn(async move {
        let mut last_bounds: Option<(i32, i32, i32, i32)> = None;

        loop {
            tokio::time::sleep(Duration::from_millis(8)).await; // ~120fps

            if !SNAP_ENABLED.load(Ordering::SeqCst) {
                last_bounds = None;
                continue;
            }

            if let Some(window) = handle.get_window("main") {
                if let Some(bounds) = get_studio_window_bounds() {
                    // Only update if bounds changed
                    if last_bounds != Some(bounds) {
                        let _ = position_next_to_studio(&window);
                        last_bounds = Some(bounds);
                    }
                }
            }
        }
    });
}

fn main() {
    // Initialize logging
    tracing_subscriber::fmt::init();

    // Build system tray menu
    let quit = CustomMenuItem::new("quit".to_string(), "Quit Bakable");
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
        .invoke_handler(tauri::generate_handler![snap_to_studio, get_snap_status])
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
                                    .title("Bakable")
                                    .body("Plugin reinstalled successfully! Restart Roblox Studio to use it.")
                                    .show();
                            }
                            Err(e) => {
                                error!("Failed to reinstall plugin: {}", e);
                                let _ = tauri::api::notification::Notification::new(&app.config().tauri.bundle.identifier)
                                    .title("Bakable Error")
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
            info!("Bakable Desktop starting up...");

            // Install plugin on first run
            match plugin::install_plugin() {
                Ok(installed) => {
                    if installed {
                        info!("Plugin installed successfully");
                        let _ = tauri::api::notification::Notification::new(&app.config().tauri.bundle.identifier)
                            .title("Bakable")
                            .body("Plugin installed! Open Roblox Studio to use Bakable.")
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

            // Start snap-to-studio monitor
            start_snap_monitor(app.handle());

            // Update tray status
            let tray_handle = app.tray_handle();
            let _ = tray_handle.get_item("status").set_title("Status: Running (port 4850)");

            info!("Bakable Desktop ready");
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
