import AppKit
import IOKit
import IOKit.ps
import ServiceManagement

// LidAwake: on AC power the Mac stays awake with the lid closed; on battery it sleeps as usual.
// It flips the system-wide `pmset disablesleep` flag (there is no per-power-source version of it)
// whenever the power source changes. It never touches display sleep, so video wake locks and
// screen lock behave normally.

let defaults = UserDefaults.standard
let kEnabled = "enabled"
defaults.register(defaults: [kEnabled: true])
let pmset = "/usr/bin/pmset"

@discardableResult
func run(_ path: String, _ args: [String]) -> (status: Int32, out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return (-1, "\(error)") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self))
}

func onAC() -> Bool {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
    return (type as String) == "AC Power"
}

func lidClosed() -> Bool {
    let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    guard root != 0 else { return false }
    defer { IOObjectRelease(root) }
    let value = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    return (value as? Bool) ?? false
}

/// Current `SleepDisabled` value from `pmset -g`, or nil when it cannot be read.
func sleepDisabled() -> Bool? {
    for line in run(pmset, ["-g"]).out.split(separator: "\n") where line.contains("SleepDisabled") {
        return line.split(whereSeparator: { $0 == " " || $0 == "\t" }).last.map { $0 == "1" }
    }
    return nil
}

/// Needs the sudoers rule from install-sudoers.sh; `sudo -n` fails instead of asking for a password.
@discardableResult
func setSleepDisabled(_ on: Bool) -> Bool {
    run("/usr/bin/sudo", ["-n", pmset, "-a", "disablesleep", on ? "1" : "0"]).status == 0
}

nonisolated(unsafe) weak var shared: AppDelegate?
nonisolated(unsafe) var lidNotifier: io_object_t = 0
nonisolated(unsafe) var lidPort: IONotificationPortRef?
let kIOPMMessageClamshellStateChange: UInt32 = 0xe0034100

/// Calls back on the main run loop whenever the lid opens or closes.
func watchLid() {
    let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    guard root != 0, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
    defer { IOObjectRelease(root) }
    CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)
    IOServiceAddInterestNotification(port, root, kIOGeneralInterest, { _, _, messageType, _ in
        guard messageType == kIOPMMessageClamshellStateChange else { return }
        MainActor.assumeIsolated { shared?.lidChanged() }
    }, nil, &lidNotifier)
    lidPort = port
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "", action: #selector(toggleEnabled), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "로그인 시 실행", action: #selector(toggleLogin), keyEquivalent: "")
    private var powerSource: CFRunLoopSource?
    private var lastError: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        shared = self
        let menu = NSMenu()
        statusLine.isEnabled = false
        toggleItem.target = self
        loginItem.target = self
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(toggleItem)
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "종료", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu

        // Fires on every plug / unplug. It runs on the main run loop, so the main actor is safe here.
        if let source = IOPSNotificationCreateRunLoopSource({ _ in
            MainActor.assumeIsolated { shared?.apply() }
        }, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSource = source
        }
        watchLid()
        apply()
    }

    /// Lid closed while staying awake: turn the display off now. With "require password immediately"
    /// this also locks the screen, which normally happens only because the Mac goes to sleep.
    func lidChanged() {
        guard lidClosed() else { return }
        if sleepDisabled() == true {
            run(pmset, ["displaysleepnow"])
        } else if !onAC() {
            apply()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Never leave the Mac unable to sleep after the app is gone.
        if sleepDisabled() == true { setSleepDisabled(false) }
    }

    func apply() {
        let ac = onAC()
        let want = defaults.bool(forKey: kEnabled) && ac
        lastError = nil
        if sleepDisabled() != want, !setSleepDisabled(want) {
            lastError = "권한 없음 · install-sudoers.sh 를 실행하세요"
        }
        // Unplugged with the lid already closed: clearing the flag alone may not put the Mac to sleep.
        if !ac, lidClosed() {
            run("/usr/bin/sudo", ["-n", pmset, "sleepnow"])
        }
        refresh(ac: ac)
    }

    private func refresh(ac: Bool) {
        let awake = sleepDisabled() == true
        statusItem.button?.image = NSImage(systemSymbolName: awake ? "laptopcomputer" : "moon.zzz",
                                           accessibilityDescription: "LidAwake")
        if let lastError {
            statusLine.title = lastError
        } else if awake {
            statusLine.title = "어댑터 연결 · 뚜껑 닫아도 깨어 있음"
        } else if !defaults.bool(forKey: kEnabled) {
            statusLine.title = "꺼짐 · 뚜껑 닫으면 잠듦"
        } else {
            statusLine.title = ac ? "어댑터 연결 · 상태 확인 필요" : "배터리 · 뚜껑 닫으면 잠듦"
        }
        toggleItem.title = defaults.bool(forKey: kEnabled) ? "끄기" : "켜기"
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func toggleEnabled() {
        defaults.set(!defaults.bool(forKey: kEnabled), forKey: kEnabled)
        apply()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("LidAwake login item: \(error)")
        }
        refresh(ac: onAC())
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
