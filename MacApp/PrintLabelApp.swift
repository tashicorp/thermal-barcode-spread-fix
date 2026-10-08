// Print Label.app: adds "Print Label" to Finder's right-click menu for PDFs (an NSServices
// entry, the same mechanism Ghostty uses for "New Ghostty Tab Here"), and also handles
// Open With. Runs the bundled print-label on the default printer with its default settings.
//
// Test without printing: "Print Label.app/Contents/MacOS/PrintLabel" --dry-run label.pdf
import AppKit
import UserNotifications

let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/PrintLabel.log")

func log(_ text: String) {
    let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(text)\n"
    if let h = try? FileHandle(forWritingTo: logURL) {
        h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
    } else {
        try? line.write(to: logURL, atomically: true, encoding: .utf8)
    }
}

/// Runs the bundled print-label on one PDF. Returns its exit status and combined output.
func runPrintLabel(_ pdf: URL, extraArgs: [String] = []) -> (ok: Bool, output: String) {
    let tool = Bundle.main.resourceURL!.appendingPathComponent("print-label")
    let p = Process(), pipe = Pipe()
    p.executableURL = tool
    p.arguments = extraArgs + [pdf.path]
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return (false, "couldn't start \(tool.path): \(error.localizedDescription)") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    let output = String(decoding: data, as: UTF8.self)
    log("\(pdf.path) exit \(p.terminationStatus)\n\(output)")
    return (p.terminationStatus == 0, output)
}

// Command-line test mode: process without printing, report, exit.
if let i = CommandLine.arguments.firstIndex(of: "--dry-run"), i + 1 < CommandLine.arguments.count {
    let pdf = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    let out = FileManager.default.temporaryDirectory.appendingPathComponent("PrintLabel-dry-run.pdf")
    let r = runPrintLabel(pdf, extraArgs: ["--out", out.path])
    print(r.output, terminator: "")
    exit(r.ok ? 0 : 1)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pending = 0
    private var handledAny = false

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.servicesProvider = self
        // Launched by double-click with nothing to print: ask for a file.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
            guard !handledAny else { return }
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.pdf]
            panel.allowsMultipleSelection = true
            panel.message = "Choose a shipping label PDF to print"
            NSApp.activate()
            if panel.runModal() == .OK { handle(panel.urls) } else { NSApp.terminate(nil) }
        }
    }

    // Open With > Print Label
    func application(_ app: NSApplication, open urls: [URL]) { handle(urls) }

    // Right-click > Print Label (NSServices, NSMessage = printLabel)
    @objc func printLabel(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        var urls = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if urls.isEmpty, let paths = pboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            urls = paths.map { URL(fileURLWithPath: $0) }
        }
        log("service called with \(urls.map(\.path))")
        handle(urls)
    }

    private func handle(_ urls: [URL]) {
        handledAny = true
        let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        if pdfs.isEmpty { alert("Nothing to print", "Select a PDF shipping label."); finish(); return }
        pending += pdfs.count
        for pdf in pdfs {
            DispatchQueue.global().async {
                let r = runPrintLabel(pdf)
                DispatchQueue.main.async { [self] in
                    let name = pdf.lastPathComponent
                    if r.ok {
                        notify("Printed \(name)", "Barcode verified and sent to the printer.")
                    } else {
                        let tail = r.output.split(separator: "\n").suffix(6).joined(separator: "\n")
                        alert("Couldn't print \(name)", tail)
                        finish()
                    }
                }
            }
        }
    }

    private func notify(_ title: String, _ body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { [self] in
                guard granted else { alert(title, body); finish(); return }
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { err in
                    DispatchQueue.main.async { [self] in
                        if err != nil { alert(title, body) }
                        finish()
                    }
                }
            }
        }
    }

    private func alert(_ title: String, _ text: String) {
        NSApp.activate()
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }

    /// Quit once every PDF has been handled.
    private func finish() {
        pending = max(0, pending - 1)
        if pending == 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) } }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
