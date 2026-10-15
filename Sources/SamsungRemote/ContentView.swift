import SwiftUI

struct ContentView: View {
    @EnvironmentObject var tv: TVClient

    var body: some View {
        VStack(spacing: 14) {
            connectionBar
            statusLine

            HStack {
                key("power", "KEY_POWER", tint: .red)
                Spacer()
                Button { tv.powerOn() } label: { Label("Wake", systemImage: "bolt.fill") }
                    .help("Wake-on-LAN (TV must allow it in settings)")
                Spacer()
                key("rectangle.portrait.and.arrow.right", "KEY_SOURCE", help: "Source")
            }

            dpad

            HStack(spacing: 12) {
                key("arrow.uturn.backward", "KEY_RETURN", help: "Back (Esc)", shortcut: .escape)
                key("house", "KEY_HOME", help: "Home", shortcut: "h")
                key("line.3.horizontal", "KEY_MENU", help: "Menu", shortcut: "m")
                key("info.circle", "KEY_INFO", help: "Info", shortcut: "i")
            }

            HStack(spacing: 24) {
                rocker(up: "KEY_VOLUP", down: "KEY_VOLDOWN", label: "VOL", upKey: "=", downKey: "-")
                VStack(spacing: 8) {
                    key("speaker.slash", "KEY_MUTE", help: "Mute", shortcut: "0")
                }
                rocker(up: "KEY_CHUP", down: "KEY_CHDOWN", label: "CH", upKey: "]", downKey: "[")
            }

            HStack(spacing: 10) {
                key("backward.fill", "KEY_REWIND")
                key("playpause.fill", "KEY_PLAY", shortcut: .space)
                key("stop.fill", "KEY_STOP")
                key("forward.fill", "KEY_FF")
            }

            Divider()
            HStack {
                TextField("Type to TV (open its keyboard first)", text: $tv.draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(sendText)
                Button("Send", action: sendText).disabled(tv.draft.isEmpty)
            }
            .controlSize(.small)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                ForEach(TVClient.apps, id: \.id) { app in
                    Button(app.name) { tv.launch(appID: app.id) }
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
    }

    private func sendText() {
        guard !tv.draft.isEmpty else { return }
        tv.sendText(tv.draft)
        tv.draft = ""
    }

    // MARK: Pieces

    private var connectionBar: some View {
        VStack(spacing: 6) {
            HStack {
                TextField("TV IP address", text: $tv.ip)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await tv.connect() } }
                Button(tv.state == .connected ? "Reconnect" : "Connect") { Task { await tv.connect() } }
            }
            HStack {
                Button { tv.scan() } label: {
                    Label(tv.scanning ? "Scanning…" : "Find TV", systemImage: "wifi")
                }
                .disabled(tv.scanning)
                ForEach(tv.discovered, id: \.ip) { d in
                    Button("\(d.name) (\(d.ip))") {
                        tv.ip = d.ip
                        Task { await tv.connect() }
                    }
                }
                Spacer()
            }
            .controlSize(.small)
        }
    }

    private var statusLine: some View {
        let (text, color): (String, Color) = {
            switch tv.state {
            case .connected: return ("Connected" + (tv.tvName.isEmpty ? "" : " to \(tv.tvName)"), .green)
            case .connecting: return ("Connecting… accept the prompt on the TV if shown", .orange)
            case .disconnected: return ("Not connected", .secondary)
            case .failed(let msg): return (msg, .red)
            }
        }()
        return Text(text).font(.caption).foregroundStyle(color).multilineTextAlignment(.center)
    }

    private var dpad: some View {
        VStack(spacing: 6) {
            key("chevron.up", "KEY_UP", shortcut: .upArrow, size: 52)
            HStack(spacing: 6) {
                key("chevron.left", "KEY_LEFT", shortcut: .leftArrow, size: 52)
                Button { tv.press("KEY_ENTER") } label: {
                    Text("OK").font(.headline).frame(width: 52, height: 52)
                }
                .buttonStyle(RemoteButtonStyle())
                .keyboardShortcut(.return, modifiers: [])
                key("chevron.right", "KEY_RIGHT", shortcut: .rightArrow, size: 52)
            }
            key("chevron.down", "KEY_DOWN", shortcut: .downArrow, size: 52)
        }
    }

    private func rocker(up: String, down: String, label: String, upKey: KeyEquivalent, downKey: KeyEquivalent) -> some View {
        VStack(spacing: 4) {
            key("plus", up, shortcut: upKey)
            Text(label).font(.caption2).foregroundStyle(.secondary)
            key("minus", down, shortcut: downKey)
        }
    }

    private func key(_ symbol: String, _ code: String, tint: Color? = nil, help: String? = nil,
                     shortcut: KeyEquivalent? = nil, size: CGFloat = 36) -> some View {
        Button { tv.press(code) } label: {
            Image(systemName: symbol).frame(width: size, height: size == 36 ? 32 : size)
        }
        .buttonStyle(RemoteButtonStyle(tint: tint))
        .help(help ?? code.replacingOccurrences(of: "KEY_", with: "").capitalized)
        .optionalShortcut(shortcut)
    }
}

private extension View {
    @ViewBuilder func optionalShortcut(_ key: KeyEquivalent?) -> some View {
        if let key { keyboardShortcut(key, modifiers: []) } else { self }
    }
}

/// Draws its own rounded background so the height set on the label is actually honored
/// (the default macOS bezel has a fixed height).
struct RemoteButtonStyle: ButtonStyle {
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(tint ?? .primary)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.25 : 0.1))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}
