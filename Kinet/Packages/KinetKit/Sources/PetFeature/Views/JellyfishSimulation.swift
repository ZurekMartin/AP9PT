import SwiftUI

typealias Vec = SIMD2<Double>

extension Vec {
    var length: Double { (x * x + y * y).squareRoot() }
    var point: CGPoint { CGPoint(x: x, y: y) }
}

struct Interest {
    var position: Vec
    var depth: Double
}

struct SimParameters {
    var scale: Double
    var frequency: Double
    var tentacles: Int
    var reduceMotion: Bool
    var smile: Double
    var sleepy: Bool
    var sleeping: Bool = false
    var terrain: ((Double, Double) -> Double?)?
    var interests: [Interest] = []
    var topLimit: Double = 130
    var bottomLimit: Double = 700
}

struct BodyBounds {
    var minX: Double
    var maxX: Double
    var minY: Double
    var maxY: Double
    var top: Double

    func clamp(_ point: Vec) -> Vec {
        Vec(min(max(point.x, minX), maxX), min(max(point.y, minY), maxY))
    }
}

struct Plankton {
    var position: Vec
    var velocity: Vec
    var phase: Double
    var age: Double = 0
    var near: Double = 0
}

struct Bubble {
    var position: Vec
    var velocity: Vec
    var radius: Double
    var age: Double
    var phase: Double
}

struct TentacleSpec {
    var layer: Int
    var links: Int
    var width: Double
    var alpha: Double
    var length: Double
    var isArm: Bool
}

final class JellyfishSimulation {
    static let rimResolution = 9
    static let armCount = 0

    var position = Vec(0, 0)
    var velocity = Vec(0, 0)
    var angle = 0.0
    var angularVelocity = 0.0
    var phase = 0.0
    var contraction = 0.0
    var wobble = Vec(0, 0)
    var wobbleVelocity = Vec(0, 0)
    var rimOffset = [Vec](repeating: Vec(0, 0), count: JellyfishSimulation.rimResolution)
    var rimVelocity = [Vec](repeating: Vec(0, 0), count: JellyfishSimulation.rimResolution)
    var chains: [[Vec]] = []
    var previousChains: [[Vec]] = []
    var specs: [TentacleSpec] = []
    var target = Vec(0, 0)
    var depth = 0.35
    var depthTarget = 0.35
    var depthLocked = false
    var effectiveScale = 1.0
    var manualTargetTimer = 0.0
    var time = 0.0
    var blink = 0.0
    var nextBlink = 2.5
    var surprise = 0.0
    var munch = 0.0
    var look = Vec(0, 0)
    var smile = 0.5
    var plankton: [Plankton] = []
    var bubbles: [Bubble] = []
    var thrustBoost = 0.0
    var asleepAmount = 0.0
    var drowsy = 0.0
    var awakeTimer = 0.0
    var paceSpeed = 0.6
    var mouthOpen = 0.0
    var smoothVelocity = Vec(0, 0)
    var turbo = false
    var flip = 0.0
    var spin = 0.0
    var playKind: PlayKind?

    enum PlayKind { case somersault, pirouette }

    enum Expression: CaseIterable { case thinking, dreaming, astonished, curious, joy }

    var expression: Expression?
    var expressionFade = 0.0
    var forcedExpression: Expression?
    var isSleepy = false
    var pinPosition: Vec?
    var isRushingFast: Bool { turbo && manualTargetTimer > 0 && velocity.length > 45 }
    var ringBlend = 0.0
    var astonishOnArrival = false
    private var isNightSleeper = false

    private var expressionElapsed = 0.0
    private var expressionDuration = 3.5
    private var expressionCooldown = Double.random(in: 10...24)

    private var playTime = 0.0
    private var playDuration = 2.4
    private var playSign = 1.0
    private var playCooldown = Double.random(in: 22...55)
    private var lastDate: Date?
    private var initialized = false
    private var pendingFood = 0
    private var previousVelocity = Vec(0, 0)
    private var waypointTimer = 0.0
    private var visitCooldown = 12.0
    private var visitHold = 0.0
    private var visitArrived = false
    private var curiousOnArrival = false
    private var sceneWidth = 390.0

    func world(_ local: Vec, scale: Double) -> Vec {
        let c = cos(angle + flip)
        let s = sin(angle + flip)
        return position + Vec(local.x * c - local.y * s, local.x * s + local.y * c)
    }

    func widthFactor() -> Double { 1 - 0.16 * contraction }

    func spinProject(_ t: Double) -> (t: Double, depth: Double) {
        let phi = asin(min(1, max(-1, t)))
        return (sin(phi + spin), cos(phi + spin))
    }

    private func anchorProfile(index: Int, count: Int) -> (radius: Double, phase: Double) {
        let t = count == 1 ? 0 : -0.88 + 1.76 * Double(index) / Double(count - 1)
        let radii = [0.9, 0.62, 0.8, 0.52, 0.86, 0.7]
        let radius = min(0.98, max(abs(t) + 0.02, radii[index % radii.count]))
        let base = asin(min(1, max(-1, t / radius)))
        return (radius, index % 2 == 0 ? base : Double.pi - base)
    }

    func anchorDepth(index: Int) -> Double {
        let count = specs.count - Self.armCount
        if index >= count { return 1 }
        return cos(anchorProfile(index: index, count: count).phase + spin)
    }
    var renderAngle: Double { angle + flip }

    func heightFactor() -> Double { 1 + 0.12 * contraction }

    func rimDisplacement(at t: Double) -> Vec {
        guard t.isFinite else { return Vec(0, 0) }
        let n = Self.rimResolution
        let position = (min(1, max(-1, t)) + 1) / 2 * Double(n - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(n - 1, lower + 1)
        let fraction = position - Double(lower)
        return rimOffset[lower] * (1 - fraction) + rimOffset[upper] * fraction
    }

    func rimWorld(_ t: Double, scale: Double) -> Vec {
        let half = 50 * scale * widthFactor()
        return world(Vec(t * half, 0), scale: scale) + rimDisplacement(at: t)
    }

    func mouthWorld(scale: Double) -> Vec {
        world(Vec(look.x * 0.6, -70 * 0.27 * scale * heightFactor()), scale: scale) + rimDisplacement(at: 0) * 0.45
    }

    func poke() {
        wobbleVelocity += Vec(Double.random(in: -120...120), -160)
        for index in rimVelocity.indices { rimVelocity[index] += Vec(Double.random(in: -80...80), Double.random(in: -60...20)) }
        velocity += Vec(Double.random(in: -26...26), -34)
        surprise = 0.9
        if !isSleepy { show(.joy, duration: 3.6) }
        thrustBoost = 1.0
        wake()
        manualTargetTimer = max(manualTargetTimer, 0)
        endPlay()
    }

    private func wake() {
        awakeTimer = isNightSleeper ? 6 : 45
    }

    func callToDecor(at point: Vec, depth: Double) {
        guard !isSleepy else { return }
        let side: Double = point.x < sceneWidth / 2 ? 1 : -1
        steer(to: point + Vec(side * 70 * effectiveScale, -40 * effectiveScale), depth: max(0, depth - 0.1))
        astonishOnArrival = Bool.random()
    }

    func show(_ next: Expression, duration: Double) {
        expression = next
        expressionElapsed = 0
        expressionDuration = duration
    }

    func triggerPlay(_ kind: PlayKind) {
        guard playKind == nil else { return }
        beginPlay(kind)
    }

    private func beginPlay(_ kind: PlayKind) {
        playKind = kind
        playTime = 0
        playDuration = kind == .somersault ? 2.4 : 2.2
        playSign = Bool.random() ? 1 : -1
        thrustBoost = 0.8
        velocity += Vec(0, -26)
        spawnBubbles(at: mouthWorld(scale: effectiveScale), count: 4)
        show(.joy, duration: playDuration + 0.3)
    }

    private func updateExpression(dt: Double, idle: Bool, reduceMotion: Bool) {
        if let forcedExpression {
            expression = forcedExpression
            expressionFade += (1 - expressionFade) * min(1, dt * 8)
            return
        }
        if expression != nil {
            expressionElapsed += dt
            let remaining = expressionDuration - expressionElapsed
            expressionFade = min(1, expressionElapsed / 0.4, remaining / 0.5)
            if remaining <= 0 {
                expression = nil
                expressionFade = 0
            }
            return
        }
        expressionFade = 0
        guard idle, !reduceMotion, playKind == nil, !isSleepy else { return }
        expressionCooldown -= dt
        if expressionCooldown <= 0 {
            expressionCooldown = Double.random(in: 10...24)
            let options: [Expression] = [.thinking, .dreaming]
            show(options.randomElement() ?? .thinking, duration: Double.random(in: 3...4.5))
        }
    }

    private func endPlay() {
        playKind = nil
        flip = 0
        spin = 0
    }

    private func updatePlay(dt: Double, idle: Bool, reduceMotion: Bool) {
        guard let kind = playKind else {
            guard idle, !isSleepy, expression == nil, pinPosition == nil else { return }
            playCooldown -= dt
            if playCooldown <= 0 {
                playCooldown = Double.random(in: 22...55)
                beginPlay(Bool.random() ? .somersault : .pirouette)
            }
            return
        }
        playTime += dt
        let progress = min(1, playTime / playDuration)
        let eased = progress * progress * (3 - 2 * progress)
        switch kind {
        case .somersault: flip = playSign * eased * 2 * .pi
        case .pirouette: spin = playSign * eased * 2 * .pi
        }
        if progress >= 1 { endPlay() }
    }

    func steer(to point: Vec, depth: Double, turbo fast: Bool = false) {
        turbo = fast && !isSleepy
        astonishOnArrival = false
        endPlay()
        target = point + Vec(0, 36 * effectiveScale)
        manualTargetTimer = 8
        depthTarget = min(1, max(0, depth))
        visitHold = 0
        visitCooldown = 16
        wake()
        thrustBoost = 1.0
    }

    func dropFood(count: Int) {
        pendingFood = min(36, pendingFood + max(1, count))
    }

    func spawnBubbles(at point: Vec, count: Int) {
        for _ in 0..<count where bubbles.count < 12 {
            bubbles.append(Bubble(
                position: point + Vec(Double.random(in: -16...16), Double.random(in: -8...10)),
                velocity: Vec(Double.random(in: -6...6), -Double.random(in: 38...70)),
                radius: Double.random(in: 2.2...5.5),
                age: 0,
                phase: Double.random(in: 0...6.28)
            ))
        }
    }

    func distanceToBody(_ point: Vec) -> Double {
        let center = world(Vec(0, -32 * effectiveScale), scale: effectiveScale)
        return (point - center).length
    }

    func bodyBounds(width: Double, height: Double, scale: Double, depth: Double, parameters: SimParameters) -> BodyBounds {
        let side = 62 * scale + 12
        let top = parameters.topLimit + 68 * scale
        let floor = height * (0.80 - 0.20 * depth)
        let bottom = min(parameters.bottomLimit - 60 * scale, floor + 40 * scale)
        return BodyBounds(minX: side, maxX: max(side + 10, width - side), minY: top, maxY: max(top + 24, bottom), top: parameters.topLimit)
    }

    func step(date: Date, size: CGSize, parameters: SimParameters) {
        let width = Double(size.width)
        let height = Double(size.height)
        guard width > 0, height > 0 else { return }
        sceneWidth = width
        if !position.x.isFinite || !position.y.isFinite || !velocity.x.isFinite || !velocity.y.isFinite || !angle.isFinite {
            reset()
        }
        let previous = lastDate ?? date
        lastDate = date
        let dt = min(1.0 / 20.0, max(1.0 / 240.0, date.timeIntervalSince(previous)))
        time += dt
        if pinPosition != nil {
            depth = 0
            depthTarget = 0
        } else if !depthLocked {
            depth += (depthTarget - depth) * min(1, dt * 0.6)
        }
        let scale = parameters.scale * (1 - 0.5 * depth)
        effectiveScale = scale
        let calm = parameters.reduceMotion ? 0.5 : 1.0
        let bounds = bodyBounds(width: width, height: height, scale: scale, depth: depth, parameters: parameters)
        if !initialized {
            position = Vec((bounds.minX + bounds.maxX) / 2, bounds.minY + (bounds.maxY - bounds.minY) * 0.3)
            target = position
            initialized = true
            waypointTimer = 4
        }

        if pendingFood > 0 {
            let count = pendingFood
            pendingFood = 0
            wake()
            let foodBounds = bodyBounds(width: width, height: height, scale: parameters.scale, depth: 0, parameters: parameters)
            spawnPlankton(bounds: foodBounds, count: count, scale: parameters.scale)
        }
        let foodBounds = bodyBounds(width: width, height: height, scale: parameters.scale, depth: 0, parameters: parameters)
        updatePlankton(dt: dt, bounds: foodBounds, restScale: parameters.scale, scale: scale)
        updateBubbles(dt: dt)

        awakeTimer = max(0, awakeTimer - dt)
        manualTargetTimer = max(0, manualTargetTimer - dt)
        waypointTimer -= dt
        visitHold = max(0, visitHold - dt)

        let hasFood = !plankton.isEmpty
        isNightSleeper = parameters.sleeping
        let wantsSleep = parameters.sleeping && awakeTimer <= 0 && !hasFood && manualTargetTimer <= 0
        asleepAmount += ((wantsSleep ? 1 : 0) - asleepAmount) * min(1, dt * 0.9)
        drowsy += (((parameters.sleepy || parameters.sleeping) && !wantsSleep ? 1 : 0) - drowsy) * min(1, dt * 2)
        isSleepy = parameters.sleepy || parameters.sleeping
        let isIdle = !hasFood && manualTargetTimer <= 0 && !wantsSleep && visitHold <= 0
        updatePlay(dt: dt, idle: isIdle, reduceMotion: parameters.reduceMotion)
        updateExpression(dt: dt, idle: isIdle, reduceMotion: parameters.reduceMotion)
        var paceTarget = 0.5
        if hasFood {
            paceTarget = 1.9
        } else if manualTargetTimer > 0 {
            paceTarget = turbo ? 3.2 : 1.6
        } else if wantsSleep {
            paceTarget = 0.12
        }
        if parameters.reduceMotion { paceTarget = min(paceTarget, 0.5) }
        paceSpeed += (paceTarget - paceSpeed) * min(1, dt * 2.2)

        if manualTargetTimer <= 0 { turbo = false }
        let mouthPoint = mouthWorld(scale: scale)
        if let nearest = plankton.min(by: { ($0.position - mouthPoint).length < ($1.position - mouthPoint).length }) {
            let mouth = mouthPoint
            target = position + (nearest.position - mouth)
            depthTarget = 0.0
            let error = nearest.position - mouth
            if error.length < 110 * scale {
                let direction = error / max(error.length, 0.001)
                velocity += direction * min(1, error.length / 40) * 150 * dt
                angularVelocity += (0 - angle) * 6 * dt
            }
        } else if manualTargetTimer > 0 {
        } else if wantsSleep {
            target = Vec((bounds.minX + bounds.maxX) / 2, bounds.maxY)
            depthTarget = 0.35
        } else if visitHold > 0 {
            if !visitArrived && (target - position).length < 55 * scale {
                visitArrived = true
                if !isSleepy && curiousOnArrival { show(.curious, duration: 3.6) }
                spawnBubbles(at: mouthWorld(scale: scale), count: 3)
                wobbleVelocity += Vec(Double.random(in: -60...60), -80)
                visitHold = min(visitHold, 3.6)
            }
        } else {
            visitCooldown -= dt
            if visitCooldown <= 0, !isSleepy, !parameters.interests.isEmpty, !parameters.reduceMotion, let interest = parameters.interests.randomElement() {
                let side: Double = interest.position.x < width / 2 ? 1 : -1
                target = interest.position + Vec(side * 78 * scale, -40 * scale)
                depthTarget = min(1, max(0, interest.depth - 0.1))
                visitHold = 12
                visitArrived = false
                curiousOnArrival = Bool.random()
                visitCooldown = Double.random(in: 18...30)
            } else if waypointTimer <= 0 {
                let d = parameters.reduceMotion ? 0.3 : Double.random(in: 0...1)
                let targetBounds = bodyBounds(width: width, height: height, scale: parameters.scale * (1 - 0.5 * d), depth: d, parameters: parameters)
                let reach = parameters.reduceMotion ? 0.3 : 1.0
                let midX = (targetBounds.minX + targetBounds.maxX) / 2
                let midY = (targetBounds.minY + targetBounds.maxY) / 2
                target = Vec(
                    midX + Double.random(in: -0.5...0.5) * (targetBounds.maxX - targetBounds.minX) * reach,
                    midY + Double.random(in: -0.5...0.5) * (targetBounds.maxY - targetBounds.minY) * reach
                )
                depthTarget = d
                waypointTimer = Double.random(in: 8...16)
            }
        }
        if astonishOnArrival {
            if manualTargetTimer <= 0 || isSleepy {
                astonishOnArrival = false
            } else if (target - position).length < 70 * scale {
                show(.astonished, duration: 3.6)
                astonishOnArrival = false
            }
        }
        target = bounds.clamp(target)
        if let terrain = parameters.terrain, let surface = terrain(target.x, depthTarget) {
            target.y = min(target.y, surface + 14 * scale)
        }

        let toTarget = target - position
        let rushing = hasFood || manualTargetTimer > 0
        let tiltLimit = turbo && manualTargetTimer > 0 ? 0.45 : 0.32
        let desired: Double
        if rushing {
            desired = toTarget.length > 90 * scale ? max(-tiltLimit, min(tiltLimit, atan2(toTarget.x, 240 * scale))) : 0
        } else {
            desired = max(-0.55, min(0.55, atan2(toTarget.x, -min(toTarget.y, 60)) * 0.6))
        }
        let turn = atan2(sin(desired - angle), cos(desired - angle))
        angularVelocity += (turn * (rushing ? 5.5 : 3.0) - angularVelocity * 3.2) * dt
        angularVelocity += sin(time * 0.7) * 0.02 * dt
        angle += angularVelocity * dt
        angle = atan2(sin(angle), cos(angle))

        let frequency = parameters.frequency * (parameters.reduceMotion ? 0.6 : 1) * (0.55 + 0.45 * paceSpeed) * (1 + 0.5 * thrustBoost)
        let previousContraction = contraction
        phase = (phase + frequency * dt).truncatingRemainder(dividingBy: 1)
        contraction = Self.contractionCurve(phase)
        var delta = contraction - previousContraction
        if delta < -0.5 { delta = 0 }
        let axis = rushing && toTarget.length > 40 * scale ? toTarget / toTarget.length : Vec(sin(angle), -cos(angle))
        let distance = toTarget.length
        let eagerness = min(1.0, 0.3 + distance / (width * 0.3))
        if delta > 0 {
            velocity += axis * (66 * delta * eagerness * calm * (1 + 0.6 * thrustBoost) * paceSpeed)
        }
        thrustBoost = max(0, thrustBoost - dt * 0.8)
        velocity.y += (toTarget.y > 12 ? 24 : 10) * dt
        velocity *= exp(-1.5 * dt)

        let soft = 10.0
        if position.x < bounds.minX + soft { velocity.x += (bounds.minX + soft - position.x) * 3 * dt }
        if position.x > bounds.maxX - soft { velocity.x -= (position.x - (bounds.maxX - soft)) * 3 * dt }
        if position.y < bounds.minY + soft { velocity.y += (bounds.minY + soft - position.y) * 3 * dt }
        if position.y > bounds.maxY - soft { velocity.y -= (position.y - (bounds.maxY - soft)) * 3 * dt }
        position += velocity * dt
        if position.x < bounds.minX { position.x = bounds.minX; velocity.x = max(0, velocity.x) }
        if position.x > bounds.maxX { position.x = bounds.maxX; velocity.x = min(0, velocity.x) }
        if position.y < bounds.minY { position.y = bounds.minY; velocity.y = max(0, velocity.y) }
        if position.y > bounds.maxY { position.y = bounds.maxY; velocity.y = min(0, velocity.y) }

        if let terrain = parameters.terrain, let surface = terrain(position.x, depth) {
            let limit = surface + 14 * scale
            if position.y > limit {
                position.y = limit
                velocity.y = min(0, velocity.y)
            }
        }
        if let pin = pinPosition {
            position = pin
            velocity = Vec(0, 0)
            angle = 0
            angularVelocity = 0
        }
        smoothVelocity += (velocity - smoothVelocity) * min(1, dt * 3)
        updateBody(dt: dt, scale: scale)
        updateChains(dt: dt, scale: scale, count: parameters.tentacles, calm: calm)
        updateFace(dt: dt, scale: scale, parameters: parameters)
        previousVelocity = velocity
    }

    static func contractionCurve(_ phase: Double) -> Double {
        if phase < 0.28 {
            return sin(phase / 0.28 * .pi / 2)
        }
        let p = (phase - 0.28) / 0.72
        return 1 - (0.5 - 0.5 * cos(p * .pi))
    }

    private func updateBody(dt: Double, scale: Double) {
        let wobbleTarget = velocity * -0.06
        let wobbleAcceleration = (wobbleTarget - wobble) * 38 - wobbleVelocity * 5.0
        wobbleVelocity += wobbleAcceleration * dt
        wobble += wobbleVelocity * dt
        wobble = Vec(max(-24, min(24, wobble.x)), max(-24, min(24, wobble.y)))
        let n = Self.rimResolution
        let acceleration = (velocity - previousVelocity) / max(dt, 0.001)
        for index in 0..<n {
            let t = Double(index) / Double(n - 1) * 2 - 1
            let weight = 0.6 + 0.4 * abs(t)
            let drag = velocity * -0.075 * weight + acceleration * -0.004
            let flare = Vec(t * 6 * scale * contraction * -1, -3 * scale * contraction)
            let stiffness = 52 + 14 * sin(Double(index) * 1.37)
            let force = (drag + flare - rimOffset[index]) * stiffness - rimVelocity[index] * 5.2
            rimVelocity[index] += force * dt
            rimOffset[index] += rimVelocity[index] * dt
            let limit = 26.0 * scale
            if rimOffset[index].length > limit { rimOffset[index] *= limit / rimOffset[index].length }
        }
    }

    private func buildSpecs(count: Int) -> [TentacleSpec] {
        let layers = [1, 0, 2, 1, 2, 0, 1, 2, 0]
        var result: [TentacleSpec] = []
        for index in 0..<count {
            let layer = layers[index % layers.count]
            result.append(TentacleSpec(
                layer: layer,
                links: 11 + (index * 5) % 7,
                width: [2.6, 3.8, 5.0][layer],
                alpha: [0.38, 0.58, 0.8][layer],
                length: 0.85 + 0.5 * abs(sin(Double(index) * 2.399)),
                isArm: false
            ))
        }
        for _ in 0..<Self.armCount {
            result.append(TentacleSpec(layer: 1, links: 9, width: 10, alpha: 0.62, length: 0.9, isArm: true))
        }
        return result
    }

    private func updateChains(dt: Double, scale: Double, count: Int, calm: Double) {
        let total = count + Self.armCount
        let target = playKind == .pirouette ? 1.0 : 0.0
        ringBlend += (target - ringBlend) * min(1, dt * 5)
        if abs(target - ringBlend) < 0.002 { ringBlend = target }
        if chains.count != total { rebuildChains(count: count, scale: scale) }
        let axis = Vec(sin(angle), -cos(angle))
        let lateral = Vec(cos(angle), sin(angle))
        let speed = smoothVelocity.length
        for index in 0..<total {
            let spec = specs[index]
            let anchor = anchorPoint(index: index, count: count, scale: scale)
            let baseSegment = 7 * scale * spec.length * (spec.isArm ? 0.85 : 1) * (1 - 0.15 * contraction)
            let links = spec.links
            chains[index][0] = anchor
            previousChains[index][0] = anchor
            let seed = Double(index)
            let layerFactor = [0.7, 1.0, 1.25][spec.layer]
            let noiseAmp = (70 + speed * 0.3) * calm * layerFactor * (0.6 + 0.2 * paceSpeed) * (1 - 0.6 * asleepAmount)
            for link in 1..<links {
                let depthAlong = Double(link) / Double(links)
                let current = chains[index][link]
                let momentum = (current - previousChains[index][link]) * (0.93 - 0.8 * ringBlend)
                previousChains[index][link] = current
                let wave = sin(time * 0.75 - Double(link) * 0.5 + seed * 0.28)
                var force = lateral * (wave * noiseAmp * depthAlong)
                force -= axis * (300 * (1 - 0.5 * contraction) * (0.6 + 0.4 * min(1.6, paceSpeed)))
                force.y += 150 + 140 * asleepAmount
                force -= smoothVelocity * (2.6 * depthAlong)
                var next = current + momentum + force * dt * dt * 0.45 * (1 - 0.85 * ringBlend)
                if ringBlend > 0.001 {
                    let hang = anchor - axis * (baseSegment * Double(link))
                    next += (hang - next) * 0.3 * ringBlend
                }
                if ringBlend > 0.01 {
                    let limit = 50 * scale * widthFactor() * 0.85
                    let side = (next - position).x * lateral.x + (next - position).y * lateral.y
                    let clamped = max(-limit, min(limit, side))
                    next += lateral * ((clamped - side) * min(1, ringBlend * 1.5))
                }
                chains[index][link] = next
            }
            for link in 1..<links {
                let parent = chains[index][link - 1]
                var direction = chains[index][link] - parent
                let length = max(direction.length, 0.0001)
                direction /= length
                chains[index][link] = parent + direction * baseSegment
            }
            if links > 3 {
                for link in 2..<(links - 1) {
                    let mid = (chains[index][link - 1] + chains[index][link + 1]) / 2
                    chains[index][link] += (mid - chains[index][link]) * 0.18
                }
            }
        }
    }

    private func rebuildChains(count: Int, scale: Double) {
        specs = buildSpecs(count: count)
        chains = []
        previousChains = []
        for index in 0..<specs.count {
            let anchor = anchorPoint(index: index, count: count, scale: scale)
            let segment = 7 * scale * specs[index].length
            let chain = (0..<specs[index].links).map { anchor + Vec(0, Double($0) * segment) }
            chains.append(chain)
            previousChains.append(chain)
        }
    }

    func anchorPoint(index: Int, count: Int, scale: Double) -> Vec {
        if index >= count {
            let arm = index - count
            let t = spinProject((Double(arm) - 1) * 0.28).t
            return world(Vec(t * 50 * scale * widthFactor(), -4 * scale), scale: scale) + rimDisplacement(at: t) * 0.9
        }
        let profile = anchorProfile(index: index, count: count)
        return rimWorld(profile.radius * sin(profile.phase + spin) * (1 - 0.25 * ringBlend), scale: scale)
    }

    private func updateFace(dt: Double, scale: Double, parameters: SimParameters) {
        nextBlink -= dt
        if nextBlink <= 0 && blink <= 0 {
            blink = 0.001
            nextBlink = Double.random(in: 2.4...6)
        }
        if blink > 0 {
            blink += dt / 0.16
            if blink >= 2 { blink = 0 }
        }
        surprise = max(0, surprise - dt)
        munch = max(0, munch - dt * 0.8)
        let mouth = mouthWorld(scale: scale)
        let nearFood = plankton.contains { ($0.position - mouth).length < 110 * scale }
        mouthOpen += ((nearFood ? 1 : 0) - mouthOpen) * min(1, dt * 6)
        let lookTarget = velocity * 0.05
        look += (lookTarget - look) * min(1, dt * 4)
        let limit = 3.2
        if look.length > limit { look *= limit / look.length }
        smile += (parameters.smile - smile) * min(1, dt * 2)
    }

    var eyeOpenness: Double {
        if blink > 0 {
            let p = blink <= 1 ? blink : 2 - blink
            return 1 - p
        }
        return 1
    }

    private func spawnPlankton(bounds: BodyBounds, count: Int, scale: Double) {
        let room = 36 - plankton.count
        let amount = min(room, max(1, count))
        guard amount > 0 else { return }
        let lowest = bounds.maxY - 19 * scale
        for _ in 0..<amount {
            plankton.append(Plankton(
                position: Vec(Double.random(in: bounds.minX...bounds.maxX), Double.random(in: (bounds.top + 20)...max(bounds.top + 40, lowest * 0.7))),
                velocity: Vec(0, Double.random(in: 6...10)),
                phase: Double.random(in: 0...6.28)
            ))
        }
    }

    private func updatePlankton(dt: Double, bounds: BodyBounds, restScale: Double, scale: Double) {
        guard !plankton.isEmpty else { return }
        let mouth = mouthWorld(scale: scale)
        let rest = bounds.maxY - 19 * restScale
        var eaten = false
        for index in plankton.indices {
            plankton[index].age += dt
            plankton[index].position.x = min(max(plankton[index].position.x + sin(time * 1.1 + plankton[index].phase) * 6 * dt, bounds.minX), bounds.maxX)
            plankton[index].position.y = min(plankton[index].position.y + plankton[index].velocity.y * dt, rest)
            let distance = (plankton[index].position - mouth).length
            plankton[index].near = distance < 45 * scale ? plankton[index].near + dt : 0
            if distance < 15 * scale || plankton[index].near > 2.5 {
                plankton[index].age = .infinity
                eaten = true
            }
        }
        if eaten { munch = 1 }
        plankton.removeAll { $0.age >= 240 }
    }

    private func updateBubbles(dt: Double) {
        guard !bubbles.isEmpty else { return }
        for index in bubbles.indices {
            bubbles[index].age += dt
            bubbles[index].position.x += sin(time * 3 + bubbles[index].phase) * 8 * dt + bubbles[index].velocity.x * dt
            bubbles[index].position.y += bubbles[index].velocity.y * dt
        }
        bubbles.removeAll { $0.age >= 2.4 }
    }

    private func reset() {
        initialized = false
        velocity = Vec(0, 0)
        angle = 0
        angularVelocity = 0
        wobble = Vec(0, 0)
        wobbleVelocity = Vec(0, 0)
        rimOffset = [Vec](repeating: Vec(0, 0), count: Self.rimResolution)
        rimVelocity = [Vec](repeating: Vec(0, 0), count: Self.rimResolution)
        chains = []
        previousChains = []
        look = Vec(0, 0)
        smoothVelocity = Vec(0, 0)
    }
}
