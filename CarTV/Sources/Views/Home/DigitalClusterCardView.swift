import SwiftUI

public struct DigitalClusterCardView: View {
    @ObservedObject var hud: SatelliteHUDService
    @State private var isPulsing: Bool = false
    @State private var navigateToCockpit: Bool = false
    
    // Core Automotive Green & Dark Black Color Palette
    private let neonGreen = Color(red: 0.0, green: 1.0, blue: 0.53) // #00FF87 Electric Neon Green
    private let emeraldGlow = Color(red: 0.02, green: 0.85, blue: 0.45)
    private let darkBgTop = Color(red: 0.04, green: 0.05, blue: 0.04)
    private let darkBgBottom = Color(red: 0.01, green: 0.015, blue: 0.01)
    
    public init(hud: SatelliteHUDService) {
        self.hud = hud
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Top Status Bar
            HStack(alignment: .center) {
                // Live Satellite Pulse Indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(hud.isSatelliteConnected ? neonGreen : Color.orange)
                        .frame(width: 8, height: 8)
                        .scaleEffect(isPulsing ? 1.25 : 0.85)
                        .shadow(color: (hud.isSatelliteConnected ? neonGreen : Color.orange).opacity(0.85), radius: isPulsing ? 6 : 2)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)
                    
                    Text(hud.isSatelliteConnected ? "GPS SAT-LOCK: ACTIVE" : "ACQUIRING SATELLITES...")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(hud.isSatelliteConnected ? neonGreen : .orange)
                        .tracking(0.6)
                }
                
                Spacer()
                
                // Unit Switcher Pill Button (Interactive tap without navigating)
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        hud.toggleUnit()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(hud.speedUnit.rawValue.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(neonGreen)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(neonGreen.opacity(0.4), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .highPriorityGesture(
                    TapGesture().onEnded {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            hud.toggleUnit()
                        }
                    }
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)
            
            // MARK: - Main Instruments Cluster
            HStack(spacing: 12) {
                // 1. Digital Speedometer with Dynamic Arc Gauge
                speedometerGauge
                    .frame(maxWidth: .infinity)
                
                // Vertical Glass Divider
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.clear, neonGreen.opacity(0.25), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 1, height: 90)
                
                // 2. Dynamic Altimeter Module
                altimeterGauge
                    .frame(maxWidth: .infinity)
                
                // Vertical Glass Divider
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.clear, neonGreen.opacity(0.25), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 1, height: 90)
                
                // 3. Dynamic Rotating Compass Gauge
                compassGauge
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            // MARK: - Bottom Action: Cockpit HUD Link
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(neonGreen.opacity(0.18))
                        .frame(width: 28, height: 28)
                    Image(systemName: "speedometer")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(neonGreen)
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("Open Full Cockpit Telemetry")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Full-screen digital speedometer & trip telemetry")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(neonGreen)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(neonGreen.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            navigateToCockpit = true
        }
        .navigationDestination(isPresented: $navigateToCockpit) {
            SatelliteHUDView()
        }
        .background(
            ZStack {
                // Pitch Dark Black Cockpit Background
                LinearGradient(
                    colors: [darkBgTop, darkBgBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // High-tech Electric Neon Green Radial Glow
                RadialGradient(
                    gradient: Gradient(colors: [
                        neonGreen.opacity(0.08),
                        Color.clear
                    ]),
                    center: .top,
                    startRadius: 20,
                    endRadius: 220
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            neonGreen.opacity(0.5),
                            Color.white.opacity(0.08),
                            neonGreen.opacity(0.25)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        )
        .shadow(color: Color.black, radius: 16, x: 0, y: 8)
        .onAppear {
            isPulsing = true
        }
    }
    
    // MARK: - 1. Speedometer Subview (Digital Digits + Dynamic Arc in Green & Black)
    private var speedometerGauge: some View {
        let speedVal = (hud.speedUnit == .kmh) ? hud.currentSpeedKmh : hud.currentSpeedMph
        let maxScale: Double = (hud.speedUnit == .kmh) ? 200.0 : 120.0
        let progress = min(max(speedVal / maxScale, 0.0), 1.0)
        
        return VStack(spacing: 2) {
            ZStack {
                // Background Track Arc (240-degree sweep)
                ClusterArcShape(startAngle: 150, sweepAngle: 240)
                    .stroke(
                        Color.white.opacity(0.08),
                        style: StrokeStyle(lineWidth: 6.5, lineCap: .round)
                    )
                    .frame(width: 82, height: 82)
                
                // Active Glowing Neon Green Speed Progress Arc
                ClusterArcShape(startAngle: 150, sweepAngle: 240 * progress)
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
                        style: StrokeStyle(lineWidth: 6.5, lineCap: .round)
                    )
                    .frame(width: 82, height: 82)
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: speedVal)
                    .shadow(color: neonGreen.opacity(0.75), radius: 7)
                
                // Digital Speed Digits (Automotive Readout)
                VStack(spacing: 0) {
                    Text(hud.formattedSpeed)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                        .shadow(color: neonGreen.opacity(0.5), radius: 5)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    
                    Text(hud.speedUnit.rawValue.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(neonGreen)
                        .tracking(0.6)
                }
            }
            .frame(height: 84)
            
            Text("SPEED")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(Color.gray.opacity(0.85))
                .tracking(1)
        }
    }
    
    // MARK: - 2. Dynamic Altimeter Subview (Vertical Ladder + Mountain in Green & Black)
    private var altimeterGauge: some View {
        let altVal = (hud.altitudeUnit == .meters) ? hud.altitudeMeters : hud.altitudeFeet
        let maxAlt = (hud.altitudeUnit == .meters) ? 1000.0 : 3300.0
        let normalizedLevel = min(max(altVal / maxAlt, 0.05), 1.0)
        let activeBars = Int(round(normalizedLevel * 6)) // 1 to 6 bars
        
        return VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.6))
                    .frame(width: 82, height: 82)
                    .overlay(
                        Circle()
                            .stroke(neonGreen.opacity(0.2), lineWidth: 1)
                    )
                
                HStack(spacing: 8) {
                    // Dynamic Vertical Altimeter Level Bars (Neon Green LEDs)
                    VStack(spacing: 3) {
                        ForEach((0..<6).reversed(), id: \.self) { barIndex in
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
                                .frame(width: 14, height: 4)
                                .shadow(
                                    color: barIndex < activeBars ? neonGreen.opacity(0.8) : .clear,
                                    radius: 3
                                )
                        }
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: altVal)
                    
                    // Numeric Altitude Readout + Mountain Icon
                    VStack(alignment: .leading, spacing: 1) {
                        Image(systemName: "mountain.2.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(neonGreen)
                            .shadow(color: neonGreen.opacity(0.6), radius: 5)
                        
                        Text(String(format: "%.0f", altVal))
                            .font(.system(size: 19, weight: .heavy, design: .monospaced))
                            .foregroundColor(.white)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                        
                        Text(hud.altitudeUnit.rawValue.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(neonGreen)
                    }
                }
            }
            .frame(height: 84)
            
            Text("ALTITUDE")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(Color.gray.opacity(0.85))
                .tracking(1)
        }
    }
    
    // MARK: - 3. Dynamic Rotating Compass Subview (Real-time Rose Dial in Green & Black)
    private var compassGauge: some View {
        VStack(spacing: 2) {
            ZStack {
                // Outer Static Dial Bezel
                Circle()
                    .fill(Color.black.opacity(0.6))
                    .frame(width: 82, height: 82)
                    .overlay(
                        Circle()
                            .stroke(neonGreen.opacity(0.2), lineWidth: 1)
                    )
                
                // Rotating Compass Dial Rose (Rotates with Vehicle/Phone Heading)
                ZStack {
                    // 12 Fine Graduation Ticks
                    ForEach(0..<12) { i in
                        Rectangle()
                            .fill(i % 3 == 0 ? neonGreen.opacity(0.7) : Color.white.opacity(0.18))
                            .frame(width: i % 3 == 0 ? 1.5 : 1, height: i % 3 == 0 ? 6 : 3.5)
                            .offset(y: -35)
                            .rotationEffect(.degrees(Double(i) * 30))
                    }
                    
                    // Cardinal Direction Points
                    Text("N")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(Color(red: 1.0, green: 0.28, blue: 0.28))
                        .offset(y: -25)
                    
                    Text("S")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .offset(y: 25)
                    
                    Text("E")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .offset(x: 25)
                    
                    Text("W")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .offset(x: -25)
                    
                    // Dual-Color Aviation Needle
                    VStack(spacing: 0) {
                        // North Needle (Vibrant Red)
                        NeedleTriangle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 1.0, green: 0.25, blue: 0.25), Color(red: 0.9, green: 0.1, blue: 0.1)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 7, height: 16)
                            .shadow(color: Color.red.opacity(0.7), radius: 3)
                        
                        // Center Pivot Dot (Neon Green)
                        Circle()
                            .fill(neonGreen)
                            .frame(width: 5, height: 5)
                            .shadow(color: neonGreen.opacity(0.9), radius: 3)
                        
                        // South Needle (Dark Emerald Tail)
                        NeedleTriangle()
                            .fill(
                                LinearGradient(
                                    colors: [neonGreen.opacity(0.4), emeraldGlow],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 7, height: 16)
                            .rotationEffect(.degrees(180))
                    }
                }
                .rotationEffect(.degrees(hud.headingDegrees))
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: hud.headingDegrees)
                
                // Fixed Top Heading Cursor (Vehicle Direction Marker in Neon Green)
                NeedleTriangle()
                    .fill(neonGreen)
                    .frame(width: 6, height: 5)
                    .rotationEffect(.degrees(180))
                    .offset(y: -39)
                    .shadow(color: neonGreen.opacity(0.8), radius: 3)
                
                // Heading Digital Readout Badge at Center Bottom (Pitch Black with Neon Green Text)
                VStack {
                    Spacer()
                    HStack(spacing: 2) {
                        Text(hud.compassDirection)
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundColor(neonGreen)
                        Text(String(format: "%.0f°", hud.headingDegrees))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Color.black.opacity(0.9))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(neonGreen.opacity(0.4), lineWidth: 0.7)
                    )
                    .offset(y: -4)
                }
            }
            .frame(height: 84)
            
            Text("HEADING")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(Color.gray.opacity(0.85))
                .tracking(1)
        }
    }
}

// MARK: - Gauge Geometry Helpers

/// Custom arc shape for circular automotive cluster gauges
private struct ClusterArcShape: Shape {
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

/// Precision triangle for compass needle pointers
private struct NeedleTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
