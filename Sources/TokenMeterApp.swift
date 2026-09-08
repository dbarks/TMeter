import SwiftUI
import AppKit
import ServiceManagement

@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var requested: Bool
    @Published private(set) var statusText = ""

    private let preferenceKey = "LaunchAtLoginRequested"
    private let service = SMAppService.mainApp

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: preferenceKey) == nil {
            defaults.set(true, forKey: preferenceKey)
        }
        requested = defaults.bool(forKey: preferenceKey)
        applyPreference()
    }

    func setEnabled(_ enabled: Bool) {
        requested = enabled
        UserDefaults.standard.set(enabled, forKey: preferenceKey)
        applyPreference()
    }

    private func applyPreference() {
        do {
            if requested && service.status != .enabled && service.status != .requiresApproval {
                try service.register()
            } else if !requested && service.status != .notRegistered {
                try service.unregister()
            }
        } catch {
            statusText = error.localizedDescription
            return
        }
        refreshStatus()
    }

    private func refreshStatus() {
        switch service.status {
        case .enabled:
            statusText = "TMeter will open when you log in."
        case .requiresApproval:
            statusText = "Allow TMeter in System Settings > General > Login Items."
        case .notRegistered:
            statusText = "TMeter will stay closed at login."
        case .notFound:
            statusText = "Login item is unavailable from this app location."
        @unknown default:
            statusText = "Login item status is unavailable."
        }
    }
}

@MainActor
final class DockTileController {
    static let shared = DockTileController()

    private let meterView = DockMeterView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))

    private init() {
        NSApplication.shared.dockTile.contentView = meterView
    }

    func update(openAI: MeterSnapshot?, claude: MeterSnapshot?) {
        meterView.chatGPTPercent = openAI.map { Int($0.contextPercent.rounded()) }
        meterView.claudePercent = claude.map { Int($0.contextPercent.rounded()) }
        meterView.needsDisplay = true
        NSApplication.shared.dockTile.display()
    }
}

final class DockMeterView: NSView {
    var chatGPTPercent: Int?
    var claudePercent: Int?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let tile = bounds.insetBy(dx: 4, dy: 4)
        let background = NSBezierPath(roundedRect: tile, xRadius: 25, yRadius: 25)
        NSGradient(starting: NSColor(calibratedRed: 0.16, green: 0.23, blue: 0.25, alpha: 1),
                   ending: NSColor(calibratedRed: 0.06, green: 0.08, blue: 0.10, alpha: 1))?.draw(in: background, angle: -90)
        NSColor.white.withAlphaComponent(0.18).setStroke()
        background.lineWidth = 1
        background.stroke()

        let titleStyle: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .bold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.72),
            .paragraphStyle: centeredStyle()
        ]
        NSString(string: "TMETER").draw(
            in: NSRect(x: 10, y: 95, width: 108, height: 20),
            withAttributes: titleStyle
        )

        drawProvider(
            name: "GPT",
            percent: chatGPTPercent,
            color: NSColor(calibratedRed: 0.20, green: 0.78, blue: 0.55, alpha: 1),
            rect: NSRect(x: 9, y: 18, width: 53, height: 72)
        )
        drawProvider(
            name: "CLD",
            percent: claudePercent,
            color: NSColor(calibratedRed: 0.94, green: 0.55, blue: 0.24, alpha: 1),
            rect: NSRect(x: 66, y: 18, width: 53, height: 72)
        )
    }

    private func drawProvider(name: String, percent: Int?, color: NSColor, rect: NSRect) {
        let panel = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
        color.withAlphaComponent(0.18).setFill()
        panel.fill()

        let nameStyle: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: color,
            .paragraphStyle: centeredStyle()
        ]
        NSString(string: name).draw(
            in: NSRect(x: rect.minX, y: rect.minY + 43, width: rect.width, height: 18),
            withAttributes: nameStyle
        )

        let valueStyle: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 18, weight: .bold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: centeredStyle()
        ]
        let value = percent.map { "\($0)%" } ?? "--"
        NSString(string: value).draw(
            in: NSRect(x: rect.minX, y: rect.minY + 16, width: rect.width, height: 24),
            withAttributes: valueStyle
        )
    }

    private func centeredStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return style
    }
}

@MainActor
final class MeterStore: ObservableObject {
    @Published var openAI: MeterSnapshot?
    @Published var claude: MeterSnapshot?
    @Published var openAIError: String?
    @Published var claudeError: String?
    @Published var lastRefresh = Date()

    private let reader = UsageReader()
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        do { openAI = try reader.readOpenAI(); openAIError = nil }
        catch { openAI = nil; openAIError = error.localizedDescription }
        do { claude = try reader.readClaude(); claudeError = nil }
        catch { claude = nil; claudeError = error.localizedDescription }
        lastRefresh = Date()
        DockTileController.shared.update(openAI: openAI, claude: claude)
    }

    var menuText: String {
        let g = openAI.map { "G \(Int($0.contextPercent.rounded()))%" } ?? "G --"
        let c = claude.map { "C \(Int($0.contextPercent.rounded()))%" } ?? "C --"
        return "\(g)  \(c)"
    }
}

enum MeterTheme {
    static let mint = Color(red: 0.12, green: 0.66, blue: 0.52)
    static let coral = Color(red: 0.86, green: 0.43, blue: 0.28)
}

struct MeterCard: View {
    let provider: String
    let snapshot: MeterSnapshot?
    let error: String?
    let color: Color
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: provider == "ChatGPT" ? "sparkle" : "sun.max")
                            .foregroundStyle(color)
                        Text(provider).font(.system(size: 19, weight: .semibold))
                    }
                    Text(provider == "ChatGPT" ? "CODEX + WORK" : "CLAUDE WORK")
                        .font(.system(size: 9, weight: .bold)).tracking(1.5)
                        .foregroundStyle(.secondary)
                    if let snapshot {
                        Text(snapshot.contextTokens.formatted())
                            .font(.system(size: 31, weight: .medium, design: .rounded))
                            .monospacedDigit()
                        Text("of \(snapshot.contextLimit.formatted()) context tokens")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    } else {
                        Text("No reading").font(.title3)
                        Text(error ?? "Waiting for session data")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle().stroke(color.opacity(0.12), lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: (snapshot?.contextPercent ?? 0) / 100)
                        .stroke(color.gradient, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 3) {
                        Text(snapshot.map { "\(Int($0.contextPercent.rounded()))%" } ?? "--")
                            .font(.system(size: 23, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("CONTEXT").font(.system(size: 8, weight: .bold)).tracking(1)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 90, height: 90)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(provider) context used")
                .accessibilityValue(snapshot.map { "\(Int($0.contextPercent.rounded())) percent" } ?? "Unavailable")
            }
            if let snapshot {
                Rectangle().fill(.primary.opacity(0.07)).frame(height: 1)
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SESSION TOKENS").font(.system(size: 8, weight: .bold)).tracking(1)
                            .foregroundStyle(.secondary)
                        Text(snapshot.sessionTokens.formatted())
                            .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                    }
                    Spacer(minLength: 0)
                    quota("SHORT WINDOW", value: snapshot.shortWindowPercent)
                    quota("WEEKLY", value: snapshot.longWindowPercent)
                }
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                    Text("Session reading")
                    Text(snapshot.updatedAt, style: .relative)
                    Text("ago")
                    Spacer()
                    if snapshot.contextLimitIsEstimated {
                        Text("Custom limit").foregroundStyle(color)
                    }
                }
                .font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 22)
                .fill(scheme == .dark ? Color.white.opacity(0.055) : Color.white.opacity(0.9))
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 22).strokeBorder(color.opacity(0.14), lineWidth: 1)
                }
                .shadow(color: .black.opacity(scheme == .dark ? 0.10 : 0.035), radius: 12, y: 5)
        }
    }

    private func quota(_ title: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 8, weight: .bold)).tracking(0.7).foregroundStyle(.secondary)
            Text(value.map { "\(Int($0.rounded()))%" } ?? "--")
                .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
            ProgressView(value: min(100, max(0, value ?? 0)), total: 100)
                .tint(color).frame(width: 66)
        }
        .help("Last recorded plan usage")
    }
}

struct MeterPanel: View {
    @ObservedObject var store: MeterStore
    @ObservedObject var loginItem: LoginItemController
    @AppStorage("ClaudeContextLimit") private var claudeContextLimit = 200_000
    @Environment(\.colorScheme) private var scheme
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(MeterTheme.mint)
                    .frame(width: 44, height: 44)
                    .background(MeterTheme.mint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 3) {
                    Text("TMeter").font(.system(size: 24, weight: .semibold, design: .rounded))
                    Text("Your context, at a glance.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: store.refresh) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .medium))
                        .frame(width: 32, height: 32)
                        .background(.primary.opacity(0.045), in: Circle())
                }
                .buttonStyle(.plain).help("Refresh usage").accessibilityLabel("Refresh usage")
            }
            .padding(.bottom, 4)

            MeterCard(provider: "ChatGPT", snapshot: store.openAI, error: store.openAIError, color: MeterTheme.mint)
            MeterCard(provider: "Claude", snapshot: store.claude, error: store.claudeError, color: MeterTheme.coral)

            DisclosureGroup(isExpanded: $showDetails) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: Binding(
                        get: { loginItem.requested },
                        set: { loginItem.setEnabled($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Open TMeter at login")
                            Text(loginItem.statusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text("Claude context limit")
                        Spacer()
                        Picker("Claude context limit", selection: $claudeContextLimit) {
                            Text("200K").tag(200_000)
                            Text("1M").tag(1_000_000)
                        }
                        .labelsHidden().pickerStyle(.segmented).frame(width: 130)
                        .onChange(of: claudeContextLimit) { store.refresh() }
                    }
                    Text("Latest local Codex and Work sessions. Standard Chat is excluded. Claude uses your selected context limit. Plan percentages reflect the last saved sample.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 12)
            } label: {
                Label("Sources & preferences", systemImage: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            HStack(spacing: 12) {
                Button("ChatGPT ↗") { openApp("/Applications/ChatGPT.app") }
                Button("Claude ↗") { openApp("/Applications/Claude.app") }
                Spacer()
                Text("15s refresh").foregroundStyle(.tertiary)
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .font(.system(size: 10, weight: .medium))
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4).padding(.top, 4)
        }
        .padding(24)
        .frame(width: 456)
        .background {
            LinearGradient(colors: scheme == .dark
                ? [Color(red: 0.09, green: 0.12, blue: 0.14), Color(red: 0.07, green: 0.08, blue: 0.10)]
                : [Color(red: 0.94, green: 0.97, blue: 0.96), Color(red: 0.97, green: 0.96, blue: 0.94)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func openApp(_ path: String) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init())
    }
}

@main
struct TMeterApp: App {
    @StateObject private var store = MeterStore()
    @StateObject private var loginItem = LoginItemController()

    var body: some Scene {
        Window("TMeter", id: "meter") {
            MeterPanel(store: store, loginItem: loginItem)
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MeterPanel(store: store, loginItem: loginItem)
        } label: {
            Label(store.menuText, systemImage: "gauge.with.dots.needle.50percent")
        }
        .menuBarExtraStyle(.window)
    }
}
