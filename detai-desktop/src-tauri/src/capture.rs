//! Screenshot capture using ScreenCaptureKit (macOS 12.3+)
//!
//! This module provides window-specific screenshot capture for Roblox Studio
//! using Apple's ScreenCaptureKit framework via Swift interop.

use std::slice;
use tracing::{info, error};

// Link to Swift functions
extern "C" {
    fn check_screen_capture_permission() -> bool;
    fn request_screen_capture_permission();
    fn get_roblox_studio_window_id() -> i64;
    fn capture_roblox_studio_window() -> *mut std::ffi::c_void;
    fn sr_data_length(ptr: *mut std::ffi::c_void) -> usize;
    fn sr_data_bytes(ptr: *mut std::ffi::c_void) -> *const u8;
    fn sr_data_free(ptr: *mut std::ffi::c_void);
}

/// Capture a screenshot of the Roblox Studio window
/// Returns PNG image data or None if capture failed
pub fn capture_studio_viewport() -> Option<Vec<u8>> {
    info!("Attempting to capture Roblox Studio viewport");

    // Check permission first
    let has_permission = unsafe { check_screen_capture_permission() };
    if !has_permission {
        error!("Screen capture permission not granted");
        unsafe { request_screen_capture_permission() };
        return None;
    }

    // Check if Roblox Studio is running
    let window_id = unsafe { get_roblox_studio_window_id() };
    if window_id == 0 {
        error!("Roblox Studio window not found");
        return None;
    }

    info!("Found Roblox Studio window with ID: {}", window_id);

    // Capture the window
    let data_ptr = unsafe { capture_roblox_studio_window() };

    if data_ptr.is_null() {
        error!("Failed to capture screenshot (null pointer returned)");
        return None;
    }

    // Get data from Swift
    let length = unsafe { sr_data_length(data_ptr) };
    let bytes_ptr = unsafe { sr_data_bytes(data_ptr) };

    if bytes_ptr.is_null() || length == 0 {
        error!("Failed to get screenshot data");
        unsafe { sr_data_free(data_ptr) };
        return None;
    }

    // Copy data to Rust Vec
    let bytes = unsafe { slice::from_raw_parts(bytes_ptr, length) };
    let result = bytes.to_vec();

    // Free Swift data
    unsafe { sr_data_free(data_ptr) };

    info!("Captured {} bytes", result.len());
    Some(result)
}

/// Check if screen capture permission is granted
pub fn has_capture_permission() -> bool {
    unsafe { check_screen_capture_permission() }
}

/// Request screen capture permission from user
pub fn request_permission() {
    unsafe { request_screen_capture_permission() }
}
