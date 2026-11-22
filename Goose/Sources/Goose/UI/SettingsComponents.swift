import SwiftUI

// MARK: - Reusable building blocks

/// Rounded, material-backed card with an optional header.
struct SettingsCard<Content: View>: View {
    let title: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
            }
            VStack(alignment: .leading, spacing: 0) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator.opacity(0.6)))
    }
}

/// Label + optional caption on the left, control on the right.
struct SettingRow<Control: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct ToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingRow(title: title, subtitle: subtitle) {
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch)
        }
    }
}

struct SliderRow: View {
    let title: String
    var subtitle: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.05
    let format: (Double) -> String

    var body: some View {
        SettingRow(title: title, subtitle: subtitle) {
            HStack(spacing: 10) {
                Slider(value: $value, in: range, step: step).frame(width: 190)
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .trailing)
            }
        }
    }
}

struct RowDivider: View {
    var body: some View { Divider().padding(.leading, 16) }
}

struct StatusDot: View {
    let on: Bool
    var body: some View {
        Circle().fill(on ? Color.green : Color.orange).frame(width: 9, height: 9)
    }
}

struct PageHeader: View {
    let title: String
    let symbol: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.tint)
            Text(title).font(.title2.weight(.semibold))
            Spacer()
        }
        .padding(.bottom, 2)
    }
}

enum Fmt {
    static func multiplier(_ v: Double) -> String { String(format: "%.2f×", v) }
    static func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
    static func seconds(_ v: Double) -> String { "\(Int(v.rounded()))s" }
}
