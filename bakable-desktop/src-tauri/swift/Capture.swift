import Foundation
import ScreenCaptureKit
import CoreGraphics
import AppKit

// MARK: - swift-rs data type
// SRData is used by swift-rs to pass byte arrays between Swift and Rust

@objc public class SRData: NSObject {
    var data: Data

    init(_ data: Data) {
        self.data = data
    }

    @objc public var count: Int {
        return data.count
    }

    @objc public func bytes() -> UnsafePointer<UInt8>? {
        return data.withUnsafeBytes { $0.baseAddress?.assumingMemoryBound(to: UInt8.self) }
    }
}

// MARK: - Exported Functions

/// Check if screen capture permission is granted
@_cdecl("check_screen_capture_permission")
public func checkScreenCapturePermission() -> Bool {
    return CGPreflightScreenCaptureAccess()
}

/// Request screen capture permission (shows system dialog)
@_cdecl("request_screen_capture_permission")
public func requestScreenCapturePermission() {
    CGRequestScreenCaptureAccess()
}

/// Get the Roblox Studio window ID (0 if not found)
@_cdecl("get_roblox_studio_window_id")
public func getRobloxStudioWindowId() -> Int64 {
    let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

    for window in windowList {
        guard let ownerName = window[kCGWindowOwnerName as String] as? String else { continue }

        if ownerName.lowercased().contains("roblox") {
            if let windowId = window[kCGWindowNumber as String] as? Int32 {
                return Int64(windowId)
            }
        }
    }

    return 0
}

/// Get Roblox Studio window bounds as (x, y, width, height) packed into Int64s
/// Returns via out parameters: x, y, w, h. Returns true if found.
@_cdecl("get_roblox_studio_window_bounds")
public func getRobloxStudioWindowBounds(_ outX: UnsafeMutablePointer<Int32>,
                                         _ outY: UnsafeMutablePointer<Int32>,
                                         _ outW: UnsafeMutablePointer<Int32>,
                                         _ outH: UnsafeMutablePointer<Int32>) -> Bool {
    let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

    for window in windowList {
        guard let ownerName = window[kCGWindowOwnerName as String] as? String else { continue }

        if ownerName.lowercased().contains("roblox") {
            if let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] {
                outX.pointee = Int32(bounds["X"] ?? 0)
                outY.pointee = Int32(bounds["Y"] ?? 0)
                outW.pointee = Int32(bounds["Width"] ?? 0)
                outH.pointee = Int32(bounds["Height"] ?? 0)
                return true
            }
        }
    }

    return false
}

/// Capture Roblox Studio window and return PNG data
@_cdecl("capture_roblox_studio_window")
public func captureRobloxStudioWindow() -> UnsafeMutableRawPointer? {
    // Try CGWindowListCreateImage first (works on all macOS versions with permission)
    if let data = captureUsingCGWindowList() {
        let srData = SRData(data)
        return Unmanaged.passRetained(srData).toOpaque()
    }

    // Fallback: try ScreenCaptureKit async approach
    let semaphore = DispatchSemaphore(value: 0)
    var resultData: Data?

    Task {
        resultData = await captureStudioWindowAsync()
        semaphore.signal()
    }

    // Wait with 10 second timeout
    if semaphore.wait(timeout: .now() + 10) == .timedOut {
        print("[Bakable] Capture timed out")
        return nil
    }

    guard let data = resultData else {
        return nil
    }

    let srData = SRData(data)
    return Unmanaged.passRetained(srData).toOpaque()
}

/// Get length of SRData
@_cdecl("sr_data_length")
public func srDataLength(_ ptr: UnsafeMutableRawPointer) -> Int {
    let srData = Unmanaged<SRData>.fromOpaque(ptr).takeUnretainedValue()
    return srData.data.count
}

/// Get bytes pointer of SRData
@_cdecl("sr_data_bytes")
public func srDataBytes(_ ptr: UnsafeMutableRawPointer) -> UnsafePointer<UInt8>? {
    let srData = Unmanaged<SRData>.fromOpaque(ptr).takeUnretainedValue()
    return srData.data.withUnsafeBytes { $0.baseAddress?.assumingMemoryBound(to: UInt8.self) }
}

/// Free SRData
@_cdecl("sr_data_free")
public func srDataFree(_ ptr: UnsafeMutableRawPointer) {
    let _ = Unmanaged<SRData>.fromOpaque(ptr).takeRetainedValue()
}

// MARK: - CGWindowList Implementation (Works on all macOS versions)

private func captureUsingCGWindowList() -> Data? {
    let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

    // Find Roblox Studio window
    var targetWindowId: CGWindowID = 0
    var targetBounds: CGRect = .zero

    for window in windowList {
        guard let ownerName = window[kCGWindowOwnerName as String] as? String else { continue }

        if ownerName.lowercased().contains("roblox") {
            if let windowId = window[kCGWindowNumber as String] as? Int32,
               let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] {
                targetWindowId = CGWindowID(windowId)
                targetBounds = CGRect(
                    x: bounds["X"] ?? 0,
                    y: bounds["Y"] ?? 0,
                    width: bounds["Width"] ?? 800,
                    height: bounds["Height"] ?? 600
                )
                break
            }
        }
    }

    guard targetWindowId != 0 else {
        print("[Bakable] Roblox Studio window not found")
        return nil
    }

    // Capture the specific window
    guard let cgImage = CGWindowListCreateImage(
        targetBounds,
        .optionIncludingWindow,
        targetWindowId,
        [.boundsIgnoreFraming, .nominalResolution]
    ) else {
        print("[Bakable] CGWindowListCreateImage failed")
        return nil
    }

    // Convert to PNG
    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    guard let tiffData = nsImage.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("[Bakable] Failed to encode PNG")
        return nil
    }

    print("[Bakable] Captured \(pngData.count) bytes (\(cgImage.width)x\(cgImage.height)) via CGWindowList")
    return pngData
}

// MARK: - ScreenCaptureKit Implementation (macOS 14.0+)

private func captureStudioWindowAsync() async -> Data? {
    // Check if SCScreenshotManager is available (macOS 14.0+)
    if #available(macOS 14.0, *) {
        return await captureWithScreenshotManager()
    } else {
        // Fall back to stream-based capture for macOS 12.3-13.x
        return await captureWithStreamOutput()
    }
}

@available(macOS 14.0, *)
private func captureWithScreenshotManager() async -> Data? {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        // Find Roblox Studio window
        guard let studioWindow = content.windows.first(where: { window in
            let appName = window.owningApplication?.applicationName ?? ""
            let bundleId = window.owningApplication?.bundleIdentifier ?? ""
            return appName.lowercased().contains("roblox") ||
                   bundleId.lowercased().contains("roblox")
        }) else {
            print("[Bakable] Roblox Studio window not found via SCK")
            return nil
        }

        print("[Bakable] Found: \(studioWindow.owningApplication?.applicationName ?? "?") - \(studioWindow.title ?? "?")")

        // Configure capture
        let config = SCStreamConfiguration()
        config.width = min(Int(studioWindow.frame.width), 1920)
        config.height = min(Int(studioWindow.frame.height), 1080)
        config.showsCursor = false
        config.pixelFormat = kCVPixelFormatType_32BGRA

        // Create filter for this window
        let filter = SCContentFilter(desktopIndependentWindow: studioWindow)

        // Capture using SCScreenshotManager (macOS 14.0+)
        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        // Convert to PNG
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            print("[Bakable] Failed to encode PNG")
            return nil
        }

        print("[Bakable] Captured \(pngData.count) bytes (\(cgImage.width)x\(cgImage.height)) via SCK")
        return pngData

    } catch {
        print("[Bakable] Capture error: \(error)")
        return nil
    }
}

// Fallback for macOS 12.3-13.x using stream output delegate
private func captureWithStreamOutput() async -> Data? {
    // For older macOS, the CGWindowList method should work
    // This is a placeholder if we need more sophisticated SCK capture
    print("[Bakable] Using CGWindowList fallback for macOS < 14.0")
    return nil
}
