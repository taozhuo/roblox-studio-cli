//! HTTP server for screenshot capture and speech
//!
//! Endpoints:
//! - GET /capture - Capture Roblox Studio viewport, returns PNG
//! - GET /health - Health check
//! - GET /permission - Check/request screen capture permission
//! - POST /speech/listen - Start speech recognition
//! - POST /speech/stop - Stop speech recognition
//! - GET /speech/transcription - Get current transcription
//! - POST /speech/speak - Text-to-speech
//! - POST /speech/silence - Stop speaking

use axum::{
    extract::Query,
    http::{header, StatusCode},
    response::{IntoResponse, Response},
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;
use tauri::AppHandle;
use tower_http::cors::{Any, CorsLayer};
use tracing::{info, error};

use crate::{capture, speech};

const PORT: u16 = 4850;

#[derive(Debug, Serialize)]
struct HealthResponse {
    status: &'static str,
    version: &'static str,
    has_capture_permission: bool,
    has_speech_permission: bool,
}

#[derive(Debug, Serialize)]
struct PermissionResponse {
    granted: bool,
    message: &'static str,
}

#[derive(Debug, Serialize)]
struct CaptureError {
    error: String,
    code: &'static str,
}

#[derive(Debug, Deserialize)]
struct CaptureQuery {
    width: Option<u32>,
    format: Option<String>,
}

#[derive(Debug, Serialize)]
struct SpeechStatus {
    listening: bool,
    speaking: bool,
    has_permission: bool,
}

#[derive(Debug, Serialize)]
struct TranscriptionResponse {
    text: Option<String>,
    listening: bool,
}

#[derive(Debug, Deserialize)]
struct SpeakRequest {
    text: String,
}

#[derive(Debug, Serialize)]
struct GenericResponse {
    success: bool,
    message: String,
}

/// Start the HTTP server for screenshot capture and speech
pub async fn start_capture_server(_app: AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    let app = Router::new()
        // Capture endpoints
        .route("/health", get(health_handler))
        .route("/permission", get(permission_handler))
        .route("/capture", get(capture_handler))
        // Speech endpoints
        .route("/speech/status", get(speech_status_handler))
        .route("/speech/listen", post(start_listen_handler))
        .route("/speech/stop", post(stop_listen_handler))
        .route("/speech/transcription", get(transcription_handler))
        .route("/speech/speak", post(speak_handler))
        .route("/speech/silence", post(silence_handler))
        .layer(cors);

    let addr = SocketAddr::from(([127, 0, 0, 1], PORT));
    info!("Starting capture server on http://{}", addr);

    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}

// MARK: - Capture Handlers

async fn health_handler() -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "ok",
        version: env!("CARGO_PKG_VERSION"),
        has_capture_permission: capture::has_capture_permission(),
        has_speech_permission: speech::has_speech_permission(),
    })
}

async fn permission_handler() -> Json<PermissionResponse> {
    if capture::has_capture_permission() {
        Json(PermissionResponse {
            granted: true,
            message: "Screen capture permission granted",
        })
    } else {
        capture::request_permission();
        Json(PermissionResponse {
            granted: false,
            message: "Permission requested. Please grant access in System Settings > Privacy > Screen Recording",
        })
    }
}

async fn capture_handler(Query(_params): Query<CaptureQuery>) -> Response {
    if !capture::has_capture_permission() {
        return (
            StatusCode::FORBIDDEN,
            Json(CaptureError {
                error: "Screen capture permission not granted. Visit /permission to request.".to_string(),
                code: "PERMISSION_DENIED",
            }),
        )
            .into_response();
    }

    match capture::capture_studio_viewport() {
        Some(png_data) => {
            info!("Screenshot captured: {} bytes", png_data.len());
            (
                StatusCode::OK,
                [(header::CONTENT_TYPE, "image/png")],
                png_data,
            )
                .into_response()
        }
        None => (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(CaptureError {
                error: "Failed to capture Roblox Studio. Is it running?".to_string(),
                code: "CAPTURE_FAILED",
            }),
        )
            .into_response(),
    }
}

// MARK: - Speech Handlers

async fn speech_status_handler() -> Json<SpeechStatus> {
    Json(SpeechStatus {
        listening: speech::is_currently_listening(),
        speaking: speech::is_currently_speaking(),
        has_permission: speech::has_speech_permission(),
    })
}

async fn start_listen_handler() -> Json<GenericResponse> {
    if !speech::has_speech_permission() {
        speech::request_stt_permission();
        return Json(GenericResponse {
            success: false,
            message: "Speech permission not granted. Please grant in System Settings > Privacy > Speech Recognition".to_string(),
        });
    }

    if speech::start_listening() {
        Json(GenericResponse {
            success: true,
            message: "Started listening".to_string(),
        })
    } else {
        Json(GenericResponse {
            success: false,
            message: "Failed to start speech recognition".to_string(),
        })
    }
}

async fn stop_listen_handler() -> Json<GenericResponse> {
    speech::stop_listening();
    Json(GenericResponse {
        success: true,
        message: "Stopped listening".to_string(),
    })
}

async fn transcription_handler() -> Json<TranscriptionResponse> {
    Json(TranscriptionResponse {
        text: speech::get_current_transcription(),
        listening: speech::is_currently_listening(),
    })
}

async fn speak_handler(Json(payload): Json<SpeakRequest>) -> Json<GenericResponse> {
    if speech::speak(&payload.text) {
        Json(GenericResponse {
            success: true,
            message: "Speaking".to_string(),
        })
    } else {
        Json(GenericResponse {
            success: false,
            message: "Failed to speak".to_string(),
        })
    }
}

async fn silence_handler() -> Json<GenericResponse> {
    speech::stop_tts();
    Json(GenericResponse {
        success: true,
        message: "Stopped speaking".to_string(),
    })
}
