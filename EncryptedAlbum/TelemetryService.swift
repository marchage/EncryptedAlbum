import Foundation
import os
#if canImport(MetricKit)
import MetricKit
#endif

/// Lightweight telemetry wrapper.
///
/// - Uses MetricKit for system/diagnostic metrics (no custom network sending).
/// - Uses `os_signpost`/`Logger` for local instrumentation which can be uplifted to MetricKit
///   via post-processing in aggregation pipelines.
/// - Strictly opt-in: nothing registers or records until `setEnabled(true)` is called.
final class TelemetryService: NSObject
{
    static let shared = TelemetryService()

    private(set) var isEnabled: Bool = false
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "EncryptedAlbum", category: "telemetry")

    private override init() {}

    /// Enable or disable telemetry. When enabling we register with MetricKit (if available).
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled

        if enabled {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        logger.log("TelemetryService: starting (opt-in)")
        #if canImport(MetricKit)
        if #available(iOS 13.0, macOS 11.0, *) {
            MXMetricManager.shared.add(self)
        }
        #endif
    }

    private func stop() {
        logger.log("TelemetryService: stopping")
        #if canImport(MetricKit)
        if #available(iOS 13.0, macOS 11.0, *) {
            MXMetricManager.shared.remove(self)
        }
        #endif
    }

    /// Record a lightweight signpost for duration/interaction measurements.
    /// The implementation is a no-op unless telemetry is enabled to avoid overhead.
    func signpost(name: StaticString, id: OSSignpostID = .exclusive, begin: Bool = true) {
        guard isEnabled else { return }
        if begin {
            os_signpost(.begin, log: .default, name: name, signpostID: id)
        } else {
            os_signpost(.end, log: .default, name: name, signpostID: id)
        }
    }
}

#if canImport(MetricKit)
@available(iOS 13.0, macOS 11.0, *)
extension TelemetryService: MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXMetricPayload]) {
        // MetricKit delivers aggregated system metrics. We intentionally do not ship
        // them out from the device in this example. Instead we log a compact summary
        // so developers can inspect logs when telemetry is enabled.
        for payload in payloads {
            logger.info("MetricKit payload received: \(String(describing: payload))")
        }
    }
}
#endif
