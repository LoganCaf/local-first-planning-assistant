import Foundation

final class SampleICSSupport {
    static let shared = SampleICSSupport()

    private init() {}

    private let sampleFileName = "SampleCanvasAssignments"
    private let sampleFileExtension = "ics"

    private var fileManager: FileManager { .default }

    private var documentsDirectory: URL? {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    var sampleFileURL: URL? {
        guard let documentsDirectory else { return nil }
        return documentsDirectory.appendingPathComponent("\(sampleFileName).\(sampleFileExtension)")
    }

    var sampleDirectoryURL: URL? {
        sampleFileURL?.deletingLastPathComponent()
    }

    func ensureSampleFileAvailable() {
        guard let sourceURL = Bundle.main.url(forResource: sampleFileName, withExtension: sampleFileExtension),
              let destinationURL = sampleFileURL else {
            return
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            return
        }

        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            #if DEBUG
            print("Failed to copy sample ICS: \(error)")
            #endif
        }
    }
}
