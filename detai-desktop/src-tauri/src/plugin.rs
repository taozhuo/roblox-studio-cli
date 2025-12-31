//! Roblox Studio plugin installer
//!
//! Handles installation of the DetAI.rbxm plugin file to the user's
//! Roblox plugins directory.

use std::fs;
use std::io::Write;
use std::path::PathBuf;
use tracing::{info, warn};

/// The plugin file bundled with the app
const PLUGIN_BYTES: &[u8] = include_bytes!("../../resources/DetAI.rbxm");

/// Get the Roblox plugins directory path
fn get_plugins_dir() -> Option<PathBuf> {
    let home = dirs::home_dir()?;

    // macOS: ~/Documents/Roblox/Plugins
    #[cfg(target_os = "macos")]
    let plugins_dir = home.join("Documents/Roblox/Plugins");

    // Windows: %LOCALAPPDATA%\Roblox\Plugins
    #[cfg(target_os = "windows")]
    let plugins_dir = dirs::data_local_dir()?.join("Roblox/Plugins");

    Some(plugins_dir)
}

/// Install the plugin to the Roblox plugins directory
/// Returns Ok(true) if installed, Ok(false) if already exists, Err on failure
pub fn install_plugin() -> Result<bool, String> {
    let plugins_dir = get_plugins_dir()
        .ok_or_else(|| "Could not determine plugins directory".to_string())?;

    // Create directory if it doesn't exist
    if !plugins_dir.exists() {
        info!("Creating plugins directory: {:?}", plugins_dir);
        fs::create_dir_all(&plugins_dir)
            .map_err(|e| format!("Failed to create plugins directory: {}", e))?;
    }

    let plugin_path = plugins_dir.join("DetAI.rbxm");

    // Check if plugin already exists with same content
    if plugin_path.exists() {
        let existing = fs::read(&plugin_path)
            .map_err(|e| format!("Failed to read existing plugin: {}", e))?;

        if existing == PLUGIN_BYTES {
            info!("Plugin already installed and up to date");
            return Ok(false);
        }

        info!("Plugin exists but outdated, updating...");
    }

    // Write the plugin file
    let mut file = fs::File::create(&plugin_path)
        .map_err(|e| format!("Failed to create plugin file: {}", e))?;

    file.write_all(PLUGIN_BYTES)
        .map_err(|e| format!("Failed to write plugin file: {}", e))?;

    info!("Plugin installed to {:?}", plugin_path);
    Ok(true)
}

/// Check if plugin is installed
pub fn is_plugin_installed() -> bool {
    get_plugins_dir()
        .map(|dir| dir.join("DetAI.rbxm").exists())
        .unwrap_or(false)
}

/// Get the plugin file path
pub fn get_plugin_path() -> Option<PathBuf> {
    get_plugins_dir().map(|dir| dir.join("DetAI.rbxm"))
}

/// Uninstall the plugin
pub fn uninstall_plugin() -> Result<(), String> {
    let plugin_path = get_plugin_path()
        .ok_or_else(|| "Could not determine plugin path".to_string())?;

    if plugin_path.exists() {
        fs::remove_file(&plugin_path)
            .map_err(|e| format!("Failed to remove plugin: {}", e))?;
        info!("Plugin uninstalled");
    } else {
        warn!("Plugin not found, nothing to uninstall");
    }

    Ok(())
}
