import Combine
import SwiftUI

struct ControlCenterView: View {
    @ObservedObject private var controller = GooseController.shared
    @ObservedObject private var settings = GooseSettings.shared
    @ObservedObject private var stats = GooseStats.shared
    @State private var isVisible = false

    private var stateInfo: (text: String, color: Color, symbol: String) {
        switch controller.state {
        case .running: return (L("Goose Running"), .green, "play.circle.fill")
        case .paused: return (L("Goose Paused"), .orange, "pause.circle.fill")
        case .hidden: return (L("Goose Hidden"), .gray, "eye.slash.circle.fill")
        case .stopped: return (L("Emergency Stop Active"), .red, "exclamationmark.octagon.fill")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                statGrid
                geeseCard
                actions
                if controller.state == .stopped {
                    Text(L("Emergency Stop halts all pranks and releases the cursor and windows. Press Resume All to continue."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .animation(.smooth(duration: 0.25), value: controller.state)
        }
        .frame(minWidth: 560, minHeight: 640)
        .onAppear {
            isVisible = true
            controller.refresh()
        }
        .onDisappear {
            isVisible = false
        }
        .task(id: isVisible) {
            guard isVisible else { return }
            while !Task.isCancelled && isVisible {
                try? await Task.sleep(for: .milliseconds(500))
                if Task.isCancelled || !isVisible { break }
                controller.refresh()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: stateInfo.symbol).font(.system(size: 34)).foregroundStyle(stateInfo.color)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 2) {
                Text(stateInfo.text).font(.title2.weight(.semibold))
                Text("\(L("Chaos Level")): \(L(settings.chaosLevel.rawValue.capitalized))\(settings.isChaosCustomized ? " · " + L("Customized") : "")")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var statGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            StatTile(title: L("Geese Count"), value: "\(controller.geese.count)", symbol: "bird")
            StatTile(title: L("Pranks Today"), value: "\(stats.pranksToday)", symbol: "theatermasks")
            StatTile(title: L("Mouse Thefts Today"), value: "\(stats.mouseTheftsToday)", symbol: "cursorarrow.motionlines")
            StatTile(title: L("Notes Today"), value: "\(stats.notesToday)", symbol: "note.text")
            StatTile(title: L("Chaos Level"), value: L(settings.chaosLevel.rawValue.capitalized), symbol: "flame")
            StatTile(title: L("AI Status"), value: controller.llm.summary, symbol: "sparkles", small: true)
            StatTile(title: L("Mouse Lock"), value: controller.mouseLockHolderName ?? L("Free"), symbol: "lock.fill", small: true)
            StatTile(title: L("Window Lock"), value: controller.windowLockHolderName ?? L("Free"), symbol: "macwindow.on.rectangle", small: true)
        }
    }

    private var geeseCard: some View {
        SettingsCard(L("Geese")) {
            if controller.geese.isEmpty {
                Text(L("No geese")).foregroundStyle(.secondary).padding(16)
            }
            ForEach(Array(controller.geese.enumerated()), id: \.element.id) { index, g in
                if index > 0 { RowDivider() }
                let lockBadge = g.holdingLock.map { " · 🔒\($0)" } ?? ""
                SettingRow(
                    title: g.name,
                    subtitle: (g.isLead ? "AI · notes · " : "") + g.personalitySummary + " · ⚡\(g.energyPercent)%" + lockBadge
                ) {
                    Text(controller.state == .running || controller.state == .stopped ? L(g.activity) : stateInfo.text)
                        .foregroundStyle(.secondary)
                }
            }
            RowDivider()
            SettingRow(title: L("Last Prank")) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(stats.lastPrank ?? L("None yet")).foregroundStyle(.secondary)
                    if let t = stats.lastPrankTime {
                        Text(t.formatted(date: .omitted, time: .standard)).font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private var actions: some View {
        let columns = [GridItem(.adaptive(minimum: 170), spacing: 10)]
        return VStack(alignment: .leading, spacing: 10) {
            Text(L("Quick Actions")).font(.footnote.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            LazyVGrid(columns: columns, spacing: 10) {
                ActionButton(L("Pause All"), "pause.fill") { controller.pauseAll() }
                    .disabled(controller.state == .paused)
                ActionButton(L("Resume All"), "play.fill") { controller.resumeAll() }
                    .disabled(controller.state == .running)
                ActionButton(controller.state == .hidden ? L("Show All") : L("Hide All"), controller.state == .hidden ? "eye" : "eye.slash") { controller.toggleHidden() }
                ActionButton(L("Spawn Goose"), "plus.circle") { controller.spawnGoose() }
                    .disabled(controller.geese.count >= settings.maxGooseCount)
                ActionButton(L("Remove All Geese"), "trash") { controller.removeAllGeese() }
                    .disabled(controller.geese.isEmpty)
                ActionButton(settings.isEnabled(.mouseTheft) ? L("Disable Mouse Theft") : L("Enable Mouse Theft"), "cursorarrow.slash") { controller.toggleMouseTheft() }
                ActionButton(settings.allPranksDisabled ? L("Enable All Pranks") : L("Disable All Pranks"), "theatermasks") { controller.toggleAllPranks() }
                ActionButton(L("Clear Mess"), "sparkles.rectangle.stack") { controller.clearDesktopMess() }
            }
            Button { controller.emergencyStop() } label: {
                Label(L("Emergency Stop"), systemImage: "exclamationmark.octagon.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
        }
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let symbol: String
    var small = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(small ? .callout.weight(.medium) : .title.weight(.semibold))
                .lineLimit(2).minimumScaleFactor(0.7).contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator.opacity(0.6)))
    }
}

private struct ActionButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    init(_ title: String, _ symbol: String, action: @escaping () -> Void) {
        self.title = title; self.symbol = symbol; self.action = action
    }

    var body: some View {
        Button(action: action) { Label(title, systemImage: symbol).frame(maxWidth: .infinity) }
            .buttonStyle(.bordered).controlSize(.large)
    }
}
