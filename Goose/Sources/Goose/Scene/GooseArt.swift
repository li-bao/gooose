import AppKit
import SpriteKit

/// Renders the goose using a skeletal rig and overlapping wide round-capped
/// lines, mirroring the original Desktop Goose drawing strategy.
@MainActor
final class GooseArt {
    let node: SKNode
    /// Footprints live in their own layer so they stay put in world space
    /// when the goose body is scaled (Settings → Goose Size).
    let marksNode = SKNode()

    private var rig = GooseRig()
    private let bodyOutline = SKShapeNode()
    private let bodyFill = SKShapeNode()
    private let underbody = SKShapeNode()
    private let neckOutline = SKShapeNode()
    private let neckFill = SKShapeNode()
    private let head1Outline = SKShapeNode()
    private let head1Fill = SKShapeNode()
    private let head2Outline = SKShapeNode()
    private let head2Fill = SKShapeNode()
    private let beak = SKShapeNode()
    private let leftEye = SKShapeNode()
    private let rightEye = SKShapeNode()
    private let shadow = SKSpriteNode()
    private let leftFoot = SKShapeNode()
    private let rightFoot = SKShapeNode()
    private var footMarkNodes: [SKShapeNode] = []

    init() {
        node = SKNode()
        configureNodes()
        attachInRenderOrder()
    }

    /// Updates the rig and redraws all body parts based on the simulation snapshot.
    func update(simulation: GooseSimulation) {
        rig.update(
            position: simulation.position,
            directionDegrees: simulation.direction,
            neckLerp: simulation.neckLerpPercent
        )
        redrawBody()
        redrawFeet(simulation: simulation)
        redrawFootMarks(simulation: simulation)
        shadow.position = simulation.position
    }

    private func configureNodes() {
        configureLine(bodyOutline, color: GooseColors.outline, width: 24)
        configureLine(bodyFill, color: GooseColors.white, width: 22)
        configureLine(underbody, color: GooseColors.outline, width: 15)
        configureLine(neckOutline, color: GooseColors.outline, width: 15)
        configureLine(neckFill, color: GooseColors.white, width: 13)
        configureLine(head1Outline, color: GooseColors.outline, width: 17)
        configureLine(head1Fill, color: GooseColors.white, width: 15)
        configureLine(head2Outline, color: GooseColors.outline, width: 12)
        configureLine(head2Fill, color: GooseColors.white, width: 10)
        configureLine(beak, color: GooseColors.orange, width: 9)

        let eyePath = CGPath(ellipseIn: CGRect(x: -2, y: -2, width: 4, height: 4), transform: nil)
        for eye in [leftEye, rightEye] {
            eye.path = eyePath
            eye.fillColor = GooseColors.eye
            eye.strokeColor = .clear
        }

        let footPath = CGPath(ellipseIn: CGRect(x: -4, y: -4, width: 8, height: 8), transform: nil)
        for foot in [leftFoot, rightFoot] {
            foot.path = footPath
            foot.fillColor = GooseColors.orange
            foot.strokeColor = .clear
        }

        let shadowSize = CGSize(width: 40, height: 30)
        if let image = makeHalftoneShadow(size: shadowSize) {
            shadow.texture = SKTexture(image: image)
        }
        shadow.size = shadowSize
        shadow.alpha = 0.85

        footMarkNodes = (0..<64).map { _ in
            Self.makeFootMarkNode()
        }
    }

    private static let webbedFootPath: CGPath = {
        let path = CGMutablePath()
        // Heel at (-4, 0), three toes spreading forward toward +X.
        path.move(to: CGPoint(x: -4.5, y: 0))
        path.addLine(to: CGPoint(x: 3.5, y: 4.0))
        path.addQuadCurve(to: CGPoint(x: 4.5, y: 0), control: CGPoint(x: 2.2, y: 1.8))
        path.addQuadCurve(to: CGPoint(x: 3.5, y: -4.0), control: CGPoint(x: 2.2, y: -1.8))
        path.closeSubpath()
        return path
    }()

    private static func makeFootMarkNode() -> SKShapeNode {
        let mark = SKShapeNode(path: webbedFootPath)
        mark.fillColor = GooseColors.mud
        mark.strokeColor = .clear
        mark.isHidden = true
        return mark
    }

    private func configureLine(_ shape: SKShapeNode, color: NSColor, width: CGFloat) {
        shape.strokeColor = color
        shape.lineWidth = width
        shape.lineCap = .round
        shape.fillColor = .clear
        shape.isAntialiased = true
    }

    private func attachInRenderOrder() {
        var z: CGFloat = 0
        for mark in footMarkNodes {
            mark.zPosition = z
            marksNode.addChild(mark)
        }
        z += 1
        let layers: [SKNode] = [
            leftFoot,
            rightFoot,
            shadow,
            bodyOutline,
            neckOutline,
            head1Outline,
            head2Outline,
            underbody,
            bodyFill,
            neckFill,
            head1Fill,
            head2Fill,
            beak,
            leftEye,
            rightEye,
        ]
        for (index, layer) in layers.enumerated() {
            layer.zPosition = z + CGFloat(index)
            node.addChild(layer)
        }
    }

    private func redrawBody() {
        let fwd = rig.forward

        let bodyStart = rig.bodyCenter + fwd * 11
        let bodyEnd = rig.bodyCenter - fwd * 11
        let bodyPath = lineSegment(from: bodyStart, to: bodyEnd)
        bodyOutline.path = bodyPath
        bodyFill.path = bodyPath

        let underStart = rig.underbodyCenter + fwd * 7
        let underEnd = rig.underbodyCenter - fwd * 7
        underbody.path = lineSegment(from: underStart, to: underEnd)

        let neckPath = lineSegment(from: rig.neckBase, to: rig.neckHeadPoint)
        neckOutline.path = neckPath
        neckFill.path = neckPath

        let head1Path = lineSegment(from: rig.neckHeadPoint, to: rig.head1EndPoint)
        head1Outline.path = head1Path
        head1Fill.path = head1Path

        let head2Path = lineSegment(from: rig.head1EndPoint, to: rig.head2EndPoint)
        head2Outline.path = head2Path
        head2Fill.path = head2Path

        let beakEnd = rig.head2EndPoint + fwd * 3
        beak.path = lineSegment(from: rig.head2EndPoint, to: beakEnd)

        let perp = rig.perpendicular
        let stretch = CGPoint(x: 1.3, y: 0.4)
        let baseX = rig.neckHeadPoint.x + fwd.x * 5
        let baseY = rig.neckHeadPoint.y + 3 + fwd.y * 5

        leftEye.position = CGPoint(
            x: baseX - perp.x * stretch.x * 5,
            y: baseY - perp.y * stretch.y * 5
        )
        rightEye.position = CGPoint(
            x: baseX + perp.x * stretch.x * 5,
            y: baseY + perp.y * stretch.y * 5
        )
    }

    private func redrawFeet(simulation: GooseSimulation) {
        leftFoot.position = simulation.lFootPos
        rightFoot.position = simulation.rFootPos
    }

    private func redrawFootMarks(simulation: GooseSimulation) {
        let settings = GooseSettings.shared
        guard settings.allows(.footprints) else {
            for node in footMarkNodes { node.isHidden = true }
            return
        }

        let targetCount = simulation.footMarks.count
        if footMarkNodes.count < targetCount {
            for _ in footMarkNodes.count..<targetCount {
                let node = Self.makeFootMarkNode()
                node.zPosition = 0
                marksNode.addChild(node)
                footMarkNodes.append(node)
            }
        } else if footMarkNodes.count > targetCount {
            while footMarkNodes.count > targetCount {
                let removed = footMarkNodes.removeLast()
                removed.removeFromParent()
            }
        }

        let lifetime = CGFloat(max(1.0, settings.footprintLifetime))
        let baseOpacity = CGFloat(min(1.0, max(0.05, settings.footprintOpacity)))
        let fadeWindow = max(0.5, min(2.0, lifetime * 0.3))

        for (index, mark) in simulation.footMarks.enumerated() {
            let node = footMarkNodes[index]
            guard mark.time > 0 else {
                node.isHidden = true
                continue
            }
            let age = GameTime.time - mark.time
            if age < 0 || age >= lifetime {
                node.isHidden = true
                continue
            }
            let fadeStart = max(0, lifetime - fadeWindow)
            let fadeFraction = age > fadeStart ? (age - fadeStart) / fadeWindow : 0
            let alpha = baseOpacity * max(0, 1 - fadeFraction)
            if alpha <= 0.02 {
                node.isHidden = true
                continue
            }
            node.isHidden = false
            node.position = mark.position
            node.zRotation = mark.angle
            node.yScale = mark.isRight ? -1 : 1
            node.alpha = alpha
        }
    }

    private func lineSegment(from a: CGPoint, to b: CGPoint) -> CGPath {
        let path = CGMutablePath()
        path.move(to: a)
        path.addLine(to: b)
        return path
    }

    private func makeHalftoneShadow(size: CGSize) -> NSImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        let bitsPerComponent = 8
        let bytesPerRow = width * 4

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.clear(CGRect(origin: .zero, size: size))
        context.addEllipse(in: CGRect(origin: .zero, size: size))
        context.clip()

        context.setFillColor(GooseColors.shadowDot.cgColor)
        for y in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) {
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }

        guard let cgImage = context.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: size)
    }
}
