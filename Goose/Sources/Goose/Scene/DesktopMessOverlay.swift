import AppKit
import SpriteKit

/// Purely visual SpriteKit overlay displaying fake documents, fake folders,
/// and fake icons inside `OverlayWindow`.
/// NEVER calls FileManager and NEVER reads, creates, moves, or deletes any real files.
@MainActor
final class DesktopMessOverlay: SKNode {
    enum ItemKind: CaseIterable, Sendable {
        case fakeDocument
        case fakeFolder
        case fakeIcon

        static let sampleNames: [ItemKind: [String]] = [
            .fakeDocument: ["honk_plan.txt", "bread_taxes.pdf", "untitled_goose.md", "todo_chaos.txt", "secrets.docx"],
            .fakeFolder:   ["Bread Stash", "Stolen Cursors", "Honk Archive", "Totally Empty"],
            .fakeIcon:     ["Honk.app", "Trash (Full)", "GooseOS.dmg", "Readme.txt"],
        ]
    }

    final class VirtualItemNode: SKNode {
        let kind: ItemKind
        let label: String

        init(kind: ItemKind, label: String) {
            self.kind = kind
            self.label = label
            super.init()
            buildVisuals()
        }

        @available(*, unavailable)
        required init?(coder aDecoder: NSCoder) {
            fatalError("not used")
        }

        private func buildVisuals() {
            switch kind {
            case .fakeDocument:
                let page = SKShapeNode(rectOf: CGSize(width: 34, height: 42), cornerRadius: 4)
                page.fillColor = NSColor(calibratedRed: 0.98, green: 0.98, blue: 0.95, alpha: 0.96)
                page.strokeColor = NSColor(calibratedWhite: 0.35, alpha: 0.9)
                page.lineWidth = 1.5
                addChild(page)

                for dy in [8, 1, -6] {
                    let line = SKShapeNode(rectOf: CGSize(width: 20, height: 2), cornerRadius: 1)
                    line.fillColor = NSColor(calibratedWhite: 0.45, alpha: 0.8)
                    line.strokeColor = .clear
                    line.position = CGPoint(x: 0, y: dy)
                    addChild(line)
                }

            case .fakeFolder:
                let tab = SKShapeNode(rectOf: CGSize(width: 18, height: 8), cornerRadius: 2)
                tab.fillColor = NSColor(calibratedRed: 0.42, green: 0.72, blue: 0.96, alpha: 0.96)
                tab.strokeColor = .clear
                tab.position = CGPoint(x: -10, y: 15)
                addChild(tab)

                let body = SKShapeNode(rectOf: CGSize(width: 42, height: 30), cornerRadius: 5)
                body.fillColor = NSColor(calibratedRed: 0.48, green: 0.77, blue: 0.98, alpha: 0.96)
                body.strokeColor = NSColor(calibratedRed: 0.25, green: 0.50, blue: 0.76, alpha: 0.9)
                body.lineWidth = 1.5
                addChild(body)

            case .fakeIcon:
                let badge = SKShapeNode(rectOf: CGSize(width: 38, height: 38), cornerRadius: 9)
                badge.fillColor = NSColor(calibratedRed: 0.95, green: 0.85, blue: 0.35, alpha: 0.96)
                badge.strokeColor = NSColor(calibratedRed: 0.72, green: 0.52, blue: 0.12, alpha: 0.9)
                badge.lineWidth = 1.5
                addChild(badge)

                let glyph = SKLabelNode(text: "🪿")
                glyph.fontSize = 20
                glyph.verticalAlignmentMode = .center
                addChild(glyph)
            }

            let pill = SKShapeNode(rectOf: CGSize(width: max(68, CGFloat(label.count) * 6.5 + 10), height: 15), cornerRadius: 4)
            pill.fillColor = NSColor(calibratedWhite: 0.08, alpha: 0.72)
            pill.strokeColor = .clear
            pill.position = CGPoint(x: 0, y: -31)
            addChild(pill)

            let text = SKLabelNode(text: label)
            text.fontName = "HelveticaNeue-Medium"
            text.fontSize = 10
            text.fontColor = .white
            text.verticalAlignmentMode = .center
            text.position = CGPoint(x: 0, y: -31)
            addChild(text)
        }
    }

    static let maxItems = 24
    private(set) var items: [VirtualItemNode] = []

    var itemCount: Int { items.count }

    func spawnMessBurst(near point: CGPoint, count: Int = 1, within bounds: CGSize) {
        for _ in 0..<max(1, count) {
            let kind = ItemKind.allCases.randomElement() ?? .fakeDocument
            let label = ItemKind.sampleNames[kind]?.randomElement() ?? "honk.txt"
            let node = VirtualItemNode(kind: kind, label: label)
            let dx = CGFloat.random(in: -55...55)
            let dy = CGFloat.random(in: -55...55)
            let x = min(max(60, point.x + dx), max(61, bounds.width - 60))
            let y = min(max(70, point.y + dy), max(71, bounds.height - 70))
            node.position = CGPoint(x: x, y: y)
            node.zRotation = CGFloat.random(in: -0.18...0.18)
            node.setScale(0.2)
            node.alpha = 0
            addChild(node)
            node.run(.group([.scale(to: 1.0, duration: 0.2), .fadeIn(withDuration: 0.2)]))
            items.append(node)
        }

        // Enforce strict bounded memory / node count.
        while items.count > Self.maxItems {
            let oldest = items.removeFirst()
            oldest.removeFromParent()
        }
    }

    func pickVirtualIcon() -> VirtualItemNode? {
        items.randomElement()
    }

    func removeItem(_ item: VirtualItemNode) {
        items.removeAll { $0 === item }
        item.removeFromParent()
    }

    func clearAll() {
        for item in items {
            item.removeFromParent()
        }
        items.removeAll()
    }

    /// Creates a transient virtual icon node (without writing anything to disk)
    /// when GooseTheftTask runs while the desktop mess layer is empty.
    static func makeTransientIcon(label: String? = nil) -> VirtualItemNode {
        let name = label ?? ItemKind.sampleNames[.fakeIcon]?.randomElement() ?? "Important.app"
        return VirtualItemNode(kind: .fakeIcon, label: name)
    }
}
