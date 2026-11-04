import SwiftUI

public struct SatelliteHUDView: View {
    @ObservedObject var hud = SatelliteHUDService.shared
    @State private var isPulsing: Bool = false
    
    // Core Automotive Green & Dark Black Palette
    private let neonGreen = Color(red: 0.0, green: 1.0, blue: 0.53)
    private let emeraldGlow = Color(red: 0.02, green: 0.85, blue: 0.45)
    private let darkBgTop = Color(red: 0.04, green: 0.05, blue: 0.04)
    private let darkBgBottom = Color(red: 0.01, green: 0.015, blue: 0.01)
    
    public init() {}
    
    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                // MARK: - 1. Top Cluster Telemetry Bar
                HStack(alignment: .center) {
                    // Live Satellite Pulse Indicator
                    HStack(spacing: 8) {
                        Circle()
                            .fill(hud.isSatelliteConnected ? neonGreen : Color.orange)
                            .frame(width: 9, height: 9)
                            .scaleEffect(isPulsing ? 1.3 : 0.85)
                            .shadow(color: (hud.isSatelliteConnected ? neonGreen : Color.orange).opacity(0.9), radius: isPulsing ? 7 : 2)
                            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text(hud.isSatelliteConnected ? "GPS SAT-LOCK: ACTIVE" : "ACQUIRING SATELLITES...")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(hud.isSatelliteConnected ? neonGreen : .orange)
                                .tracking(0.6)
                            Text("DRIVEPLAY DIGITAL CLUSTER • 60Hz")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Spacer()
                    
                    // Unit Switcher Pill Button
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            hud.toggleUnit()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(hud.speedUnit.rawValue.uppercased())
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(neonGreen)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.8))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(neonGreen.opacity(0.4), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                
                // MARK: - 2. Centerpiece: Supercar Speedometer Gauge
                speedometerClusterModule
                    .padding(.horizontal, 16)
                
                // MARK: - 3. Dual Instruments: Altimeter & Compass
                HStack(spacing: 14) {
                    altimeterModule
                    compassModule
                }
                .padding(.horizontal, 16)
                
                // MARK: - 4. Lower Telemetry: Trip Computer Cards
                HStack(spacing: 12) {
                    telemetryCard(
                        title: "TRIP DISTANCE",
                        value: hud.formattedTripDistance,
                        systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                    )
                    
                    telemetryCard(
                        title: "DURATION",
                        value: hud.formattedTripDuration,
                        systemImage: "stopwatch.fill"
                    )
                    
                    telemetryCard(
                        title: "TOP SPEED",
                        value: String(format: "%.0f %@", hud.speedUnit == .kmh ? hud.maxSpeedKmh : hud.maxSpeedMph, hud.speedUnit.rawValue),
                        systemImage: "gauge.with.needle.fill"
                    )
                }
                .padding(.horizontal, 16)
                
                // MARK: - 5. Reset Trip Computer Action
                Button {
                    withAnimation {
                        hud.resetTrip()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 13, weight: .bold))
                        Text("Reset Trip Computer")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(neonGreen)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(neonGreen.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
        .background(
            ZStack {
                Color.black.ignoresSafeArea()
                
                // Ambient Neon-Green Cockpit Glow
                RadialGradient(
                    gradient: Gradient(colors: [
                        neonGreen.opacity(0.08),
                        Color.clear
                    ]),
                    center: .top,
                    startRadius: 40,
                    endRadius: 360
                )
                .ignoresSafeArea()
            }
        )
        .navigationTitle("Cockpit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    hud.toggleUnit()
                } label: {
                    Text(hud.speedUnit.rawValue.uppercased())
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(neonGreen)
                }
            }
        }
        .onAppear {
            isPulsing = true
            hud.start()
        }
    }
    
    // MARK: - Center Grand Speedometer Module
    private var speedometerClusterModule: some View {
        let speedVal = (hud.speedUnit == .kmh) ? hud.currentSpeedKmh : hud.currentSpeedMph
        let maxScale: Double = (hud.speedUnit == .kmh) ? 200.0 : 120.0
        let progress = min(max(speedVal / maxScale, 0.0), 1.0)
        
        return VStack(spacing: 0) {
            ZStack {
                // Background Glow Disk
                Circle()
                    .fill(Color.black.opacity(0.85))
                    .frame(width: 220, height: 220)
                    .overlay(
                        Circle()
                            .stroke(neonGreen.opacity(0.15), lineWidth: 1)
                    )
                
                // Graduated Tick Marks around arc
                ForEach(0..<25) { tick in
                    Rectangle()
                        .fill(tick % 4 == 0 ? neonGreen.opacity(0.7) : Color.white.opacity(0.18))
                        .frame(width: tick % 4 == 0 ? 2 : 1, height: tick % 4 == 0 ? 8 : 4)
                        .offset(y: -100)
                        .rotationEffect(.degrees(-120 + Double(tick) * 10))
                }
                
                // Outer Track Arc (240° sweep)
                FullClusterArcShape(startAngle: 150, sweepAngle: 240)
                    .stroke(
                        Color.white.opacity(0.08),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .frame(width: 195, height: 195)
                
                // Active Glowing Neon Green Speed Arc
                FullClusterArcShape(startAngle: 150, sweepAngle: 240 * progress)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 0.0, green: 0.75, blue: 0.4),
                                neonGreen,
                                Color(red: 0.45, green: 1.0, blue: 0.25)
                            ],
                            startPoint: .bottomLeading,
                            endPoint: .topTrailing
                        ),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .frame(width: 195, height: 195)
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: speedVal)
                    .shadow(color: neonGreen.opacity(0.85), radius: 10)
                
                // Speed Digital Readout
                VStack(spacing: 2) {
                    Text("CURRENT SPEED")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.gray.opacity(0.85))
                        .tracking(1.5)
                    
                    Text(hud.formattedSpeed)
                        .font(.system(size: 70, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                        .shadow(color: neonGreen.opacity(0.55), radius: 8)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    
                    Text(hud.speedUnit.rawValue.uppercased())
                        .font(.system(size: 15, weight: .black, design: .monospaced))
                        .foregroundColor(neonGreen)
                        .tracking(1)
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(neonGreen)
                            .frame(width: 5, height: 5)
                        Text("REAL-TIME GPS")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(neonGreen.opacity(0.8))
                    }
                    .padding(.top, 4)
                }
            }
            .frame(height: 230)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [darkBgTop, darkBgBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [neonGreen.opacity(0.4), Color.white.opacity(0.08), neonGreen.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        )
        .shadow(color: Color.black, radius: 16, x: 0, y: 8)
    }
    
    // MARK: - Left Instrument: Dynamic Altimeter Module
    private var altimeterModule: some View {
        let altVal = (hud.altitudeUnit == .meters) ? hud.altitudeMeters : hud.altitudeFeet
        let maxAlt = (hud.altitudeUnit == .meters) ? 1000.0 : 3300.0
        let normalizedLevel = min(max(altVal / maxAlt, 0.05), 1.0)
        let activeBars = Int(round(normalizedLevel * 8)) // 1 to 8 bars
        
        return VStack(spacing: 8) {
            HStack {
                Text("ALTITUDE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(Color.gray.opacity(0.85))
                    .tracking(1)
                Spacer()
                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(neonGreen)
            }
            
            HStack(spacing: 12) {
                // Vertical LED Bars (8 Segment Ladder)
                VStack(spacing: 3) {
                    ForEach((0..<8).reversed(), id: \.self) { barIndex in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(
                                barIndex < activeBars
                                    ? LinearGradient(
                                        colors: [emeraldGlow, neonGreen],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                    : LinearGradient(
                                        colors: [Color.white.opacity(0.06), Color.white.opacity(0.03)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                            )
                            .frame(width: 18, height: 4)
                            .shadow(color: barIndex < activeBars ? neonGreen.opacity(0.8) : .clear, radius: 3)
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: altVal)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.0f", altVal))
                        .font(.system(size: 28, weight: .heavy, design: .monospaced))
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    
                    Text(hud.altitudeUnit.rawValue.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(neonGreen)
                    
                    Text("ELEVATION")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray)
                }
            }
            .frame(height: 70)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [darkBgTop, darkBgBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(neonGreen.opacity(0.25), lineWidth: 1)
        )
    }
    
    // MARK: - Right Instrument: Dynamic Aviation Rose Compass
    private var compassModule: some View {
        VStack(spacing: 8) {
            HStack {
                Text("HEADING")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(Color.gray.opacity(0.85))
                    .tracking(1)
                Spacer()
                Image(systemName: "safari.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(neonGreen)
            }
            
            HStack(spacing: 10) {
                // Rotating Compass Rose Dial
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.7))
                        .frame(width: 68, height: 68)
                        .overlay(
                            Circle()
                                .stroke(neonGreen.opacity(0.2), lineWidth: 1)
                        )
                    
                    // Rotating Disc
                    ZStack {
                        ForEach(0..<12) { i in
                            Rectangle()
                                .fill(i % 3 == 0 ? neonGreen.opacity(0.7) : Color.white.opacity(0.18))
                                .frame(width: i % 3 == 0 ? 1.5 : 1, height: i % 3 == 0 ? 5 : 3)
                                .offset(y: -29)
                                .rotationEffect(.degrees(Double(i) * 30))
                        }
                        
                        Text("N")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundColor(Color(red: 1.0, green: 0.28, blue: 0.28))
                            .offset(y: -20)
                        
                        Text("S")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                            .offset(y: 20)
                        
                        Text("E")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                            .offset(x: 20)
                        
                        Text("W")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                            .offset(x: -20)
                        
                    }
                    .rotationEffect(.degrees(hud.compassRoseRotationDegrees))
                    .animation(.linear(duration: 0.8), value: hud.compassRoseRotationDegrees)
                    // The needle is **fixed**: it points the way the car faces
                    // and the rose turns under it. A needle inside the rose
                    // turns with it and always says north.
                    //
                    // It is **green**, not red: red is the rose's own "N", and
                    // a red needle that always points up says "north" while
                    // the letters say something else — which is what made the
                    // compass look wrong.
                    VStack(spacing: 0) {
                        FullNeedleTriangle()
                            .fill(
                                LinearGradient(
                                    colors: [neonGreen, emeraldGlow],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 6, height: 13)
                            .shadow(color: neonGreen.opacity(0.8), radius: 2)

                        Circle()
                            .fill(neonGreen)
                            .frame(width: 4, height: 4)

                        FullNeedleTriangle()
                            .fill(
                                LinearGradient(
                                    colors: [neonGreen.opacity(0.4), emeraldGlow],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 6, height: 13)
                            .rotationEffect(.degrees(180))
                    }
                }
                
                // Digital Heading Readout Badge
                VStack(alignment: .leading, spacing: 2) {
                    Text(hud.compassDirection)
                        .font(.system(size: 22, weight: .black, design: .monospaced))
                        .foregroundColor(neonGreen)
                    
                    Text(String(format: "%.0f°", hud.headingDegrees))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    
                    Text(hud.isCompassReliable ? "BEARING" : "GPS COURSE")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(hud.isCompassReliable ? .gray : .orange)
                }
            }
            .frame(height: 70)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [darkBgTop, darkBgBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(neonGreen.opacity(0.25), lineWidth: 1)
        )
    }
    
    // MARK: - Lower Telemetry Card Helper
    @ViewBuilder
    private func telemetryCard(title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(neonGreen)
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color.gray.opacity(0.85))
            }
            
            Text(value)
                .font(.system(size: 16, weight: .heavy, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [darkBgTop, darkBgBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(neonGreen.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Full Cluster Arc Shapes

private struct FullClusterArcShape: Shape {
    var startAngle: Double
    var sweepAngle: Double
    
    var animatableData: Double {
        get { sweepAngle }
        set { sweepAngle = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard sweepAngle > 0 else { return path }
        
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startAngle),
            endAngle: .degrees(startAngle + sweepAngle),
            clockwise: false
        )
        return path
    }
}

private struct FullNeedleTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
