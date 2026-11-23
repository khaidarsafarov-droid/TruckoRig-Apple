import Foundation
import MetricKit

/// On-device crash and hang reports from MetricKit.
///
/// Nothing here is uploaded. The system hands the previous session's diagnostics to the app,
/// the app writes them to the device log, and a copy stays in Application Support. A report
/// leaves the phone only when the driver shares the log or the file.
enum DiagnosticReporter {
    private static let subscriber = Subscriber()

    static func start() {
        MXMetricManager.shared.add(subscriber)
    }

    private final class Subscriber: NSObject, MXMetricManagerSubscriber {
        func didReceive(_ payloads: [MXDiagnosticPayload]) {
            for payload in payloads {
                let crashes = payload.crashDiagnostics ?? []
                let hangs = payload.hangDiagnostics ?? []
                guard !crashes.isEmpty || !hangs.isEmpty else { continue }
                AppLog.diagnostics.error(
                    "MetricKit crashes=\(crashes.count, privacy: .public) hangs=\(hangs.count, privacy: .public)"
                )
                for crash in crashes {
                    AppLog.diagnostics.error(
                        "MetricKit crash type=\(Self.number(crash.exceptionType), privacy: .public) code=\(Self.number(crash.exceptionCode), privacy: .public) signal=\(Self.number(crash.signal), privacy: .public)"
                    )
                }
                for hang in hangs {
                    let seconds = hang.hangDuration.converted(to: .seconds).value
                    AppLog.diagnostics.error("MetricKit hang \(seconds, privacy: .public)s")
                }
                Self.store(payload)
            }
        }

        private static func number(_ value: NSNumber?) -> String {
            value.map { "\($0)" } ?? "unknown"
        }

        private static func store(_ payload: MXDiagnosticPayload) {
            let data = payload.jsonRepresentation()
            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Diagnostics", isDirectory: true)
            guard let folder else { return }
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let url = folder.appendingPathComponent("metrickit-\(Int(Date().timeIntervalSince1970)).json")
                try data.write(to: url, options: [.atomic, .completeFileProtection])
            } catch {
                AppLog.diagnostics.error("Could not store a MetricKit report: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
