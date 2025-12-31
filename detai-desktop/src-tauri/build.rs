fn main() {
    // Build Tauri
    tauri_build::build();

    // Build Swift code for ScreenCaptureKit
    #[cfg(target_os = "macos")]
    {
        use swift_rs::SwiftLinker;

        SwiftLinker::new("12.3")
            .with_package("swift", "./swift/")
            .link();
    }
}
