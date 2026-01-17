//! Speech recognition and text-to-speech using macOS APIs
//!
//! - Speech-to-Text: SFSpeechRecognizer
//! - Text-to-Speech: AVSpeechSynthesizer

use std::ffi::{CStr, CString};
use tracing::{info, error};

// Link to Swift speech functions
extern "C" {
    fn check_speech_permission() -> bool;
    fn request_speech_permission();
    fn start_speech_recognition() -> bool;
    fn stop_speech_recognition();
    fn get_transcription() -> *mut std::ffi::c_void;
    fn is_listening() -> bool;

    fn speak_text(text: *const i8) -> bool;
    fn stop_speaking();
    fn is_speaking() -> bool;

    fn sr_string_value(ptr: *mut std::ffi::c_void) -> *const i8;
    fn sr_string_free(ptr: *mut std::ffi::c_void);
}

// MARK: - Speech Recognition (STT)

/// Check if speech recognition permission is granted
pub fn has_speech_permission() -> bool {
    unsafe { check_speech_permission() }
}

/// Request speech recognition permission
pub fn request_stt_permission() {
    unsafe { request_speech_permission() }
}

/// Start listening for speech
pub fn start_listening() -> bool {
    info!("Starting speech recognition");
    unsafe { start_speech_recognition() }
}

/// Stop listening for speech
pub fn stop_listening() {
    info!("Stopping speech recognition");
    unsafe { stop_speech_recognition() }
}

/// Check if currently listening
pub fn is_currently_listening() -> bool {
    unsafe { is_listening() }
}

/// Get the current transcription
pub fn get_current_transcription() -> Option<String> {
    let ptr = unsafe { get_transcription() };

    if ptr.is_null() {
        return None;
    }

    let c_str = unsafe { sr_string_value(ptr) };
    if c_str.is_null() {
        unsafe { sr_string_free(ptr) };
        return None;
    }

    let result = unsafe { CStr::from_ptr(c_str) }
        .to_string_lossy()
        .into_owned();

    unsafe { sr_string_free(ptr) };

    if result.is_empty() {
        None
    } else {
        Some(result)
    }
}

// MARK: - Text-to-Speech (TTS)

/// Speak text aloud
pub fn speak(text: &str) -> bool {
    let c_string = match CString::new(text) {
        Ok(s) => s,
        Err(_) => {
            error!("Invalid text for TTS");
            return false;
        }
    };

    info!("Speaking: {}...", &text[..text.len().min(50)]);
    unsafe { speak_text(c_string.as_ptr()) }
}

/// Stop speaking
pub fn stop_tts() {
    unsafe { stop_speaking() }
}

/// Check if currently speaking
pub fn is_currently_speaking() -> bool {
    unsafe { is_speaking() }
}
