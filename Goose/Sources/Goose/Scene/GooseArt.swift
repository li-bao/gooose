import AppKit
import SpriteKit

/// Renders the goose into a crisp 2× Retina `SKSpriteNode` texture using
/// CoreGraphics strokes in exact Desktop Goose painter's order, avoiding
/// per-frame `SKShapeNode` open-line tessellation issues.
@MainActor
final class GooseArt {
    private static let canvasSize = CGSize(width: 140, height: 140)
    private static let retinaScale: CGFloat = 2.0

    let node: SKNode
    /// Footprints live in their own layer so they stay put in world space
    /// when the goose body is scaled (Settings → Goose Size).
    let marksNode = SKNode()

    private let shadow = SKSpriteNode()
    private let bodySprite = SKSpriteNode()
    private var footMarkNodes: [SKShapeNode] = []

    // Pose cache to avoid redundant texture uploads when stationary
    private var lastDirection: CGFloat = .nan
    private var lastNeckLerp: CGFloat = .nan
    private var lastLeftFootOffset: CGPoint = CGPoint(x: CGFloat.nan, y: CGFloat.nan)
    private var lastRightFootOffset: CGPoint = CGPoint(x: CGFloat.nan, y: CGFloat.nan)

    init() {
        node = SKNode()
        configureNodes()
        attachInRenderOrder()
    }

    /// Updates the rig and redraws the goose sprite + footprints based on the simulation snapshot.
    func update(simulation: GooseSimulation) {
        let pos = simulation.position
        shadow.position = pos
        bodySprite.position = pos
        redrawBodyIfNeeded(simulation: simulation)
        redrawFootMarks(simulation: simulation)
    }

    private func configureNodes() {
        let shadowSize = CGSize(width: 40, height: 30)
        if let image = makeHalftoneShadow(size: shadowSize) {
            shadow.texture = SKTexture(image: image)
        }
        shadow.size = shadowSize
        shadow.alpha = 0.85

        bodySprite.size = Self.canvasSize
        bodySprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        bodySprite.alpha = 1.0
        bodySprite.isHidden = false

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

    private func attachInRenderOrder() {
        for mark in footMarkNodes {
            mark.zPosition = 0
            marksNode.addChild(mark)
        }
        shadow.zPosition = 1
        bodySprite.zPosition = 2
        node.addChild(shadow)
        node.addChild(bodySprite)
    }

    private func redrawBodyIfNeeded(simulation: GooseSimulation) {
        let dir = simulation.direction
        let neck = simulation.neckLerpPercent
        let lOffset = simulation.lFootPos - simulation.position
        let rOffset = simulation.rFootPos - simulation.position

        if bodySprite.texture != nil,
           abs(dir - lastDirection) < 0.05,
           abs(neck - lastNeckLerp) < 0.005,
           abs(lOffset.x - lastLeftFootOffset.x) < 0.1,
           abs(lOffset.y - lastLeftFootOffset.y) < 0.1,
           abs(rOffset.x - lastRightFootOffset.x) < 0.1,
           abs(rOffset.y - lastRightFootOffset.y) < 0.1 {
            return
        }

        lastDirection = dir
        lastNeckLerp = neck
        lastLeftFootOffset = lOffset
        lastRightFootOffset = rOffset

        if let cgImage = renderGooseCGImage(directionDegrees: dir, neckLerp: neck, leftFootOffset: lOffset, rightFootOffset: rOffset) {
            bodySprite.texture = SKTexture(cgImage: cgImage)
        }
    }

    private func renderGooseCGImage(
        directionDegrees: CGFloat,
        neckLerp: CGFloat,
        leftFootOffset: CGPoint,
        rightFootOffset: CGPoint
    ) -> CGImage? {
        let pixelW = Int(Self.canvasSize.width * Self.retinaScale)
        let pixelH = Int(Self.canvasSize.height * Self.retinaScale)
        guard let ctx = CGContext(
            data: nil,
            width: pixelW,
            height: pixelH,
            bitsPerComponent: 8,
            bytesPerRow: pixelW * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        ctx.clear(CGRect(x: 0, y: 0, width: pixelW, height: pixelH))
        ctx.scaleBy(x: Self.retinaScale, y: Self.retinaScale)
        ctx.translateBy(x: Self.canvasSize.width * 0.5, y: Self.canvasSize.height * 0.5)
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.setLineCap(.round)

        var rig = GooseRig()
        rig.update(position: .zero2, directionDegrees: directionDegrees, neckLerp: neckLerp)

        // 1. Feet
        ctx.setFillColor(GooseColors.orange.cgColor)
        for center in [leftFootOffset, rightFootOffset] {
            ctx.fillEllipse(in: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
        }

        // 2. Outlines
        let fwd = rig.forward
        let bodyA = rig.bodyCenter + fwd * 11
        let bodyB = rig.bodyCenter - fwd * 11
        let underA = rig.underbodyCenter + fwd * 7
        let underB = rig.underbodyCenter - fwd * 7
        let beakEnd = rig.head2EndPoint + fwd * 3

        strokeLine(ctx, from: bodyA, to: bodyB, color: GooseColors.outline, width: 24)
        strokeLine(ctx, from: rig.neckBase, to: rig.neckHeadPoint, color: GooseColors.outline, width: 15)
        strokeLine(ctx, from: rig.neckHeadPoint, to: rig.head1EndPoint, color: GooseColors.outline, width: 17)
        strokeLine(ctx, from: rig.head1EndPoint, to: rig.head2EndPoint, color: GooseColors.outline, width: 12)
        strokeLine(ctx, from: underA, to: underB, color: GooseColors.outline, width: 15)

        // 3. White fills + orange beak
        strokeLine(ctx, from: bodyA, to: bodyB, color: GooseColors.white, width: 22)
        strokeLine(ctx, from: rig.neckBase, to: rig.neckHeadPoint, color: GooseColors.white, width: 13)
        strokeLine(ctx, from: rig.neckHeadPoint, to: rig.head1EndPoint, color: GooseColors.white, width: 15)
        strokeLine(ctx, from: rig.head1EndPoint, to: rig.head2EndPoint, color: GooseColors.white, width: 10)
        strokeLine(ctx, from: rig.head2EndPoint, to: beakEnd, color: GooseColors.orange, width: 9)

        // 4. Eyes
        let perp = rig.perpendicular
        let stretch = CGPoint(x: 1.3, y: 0.4)
        let baseX = rig.neckHeadPoint.x + fwd.x * 5
        let baseY = rig.neckHeadPoint.y + 3 + fwd.y * 5
        let leftEyeCenter = CGPoint(x: baseX - perp.x * stretch.x * 5, y: baseY - perp.y * stretch.y * 5)
        let rightEyeCenter = CGPoint(x: baseX + perp.x * stretch.x * 5, y: baseY + perp.y * stretch.y * 5)

        ctx.setFillColor(GooseColors.eye.cgColor)
        for center in [leftEyeCenter, rightEyeCenter] {
            ctx.fillEllipse(in: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4))
        }

        return ctx.makeImage()
    }

    private func strokeLine(_ ctx: CGContext, from a: CGPoint, to b: CGPoint, color: NSColor, width: CGFloat) {
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)
        ctx.beginPath()
        ctx.move(to: a)
        ctx.addLine(to: b)
        ctx.strokePath()
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
