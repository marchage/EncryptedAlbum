import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

enum PrivacyBackgroundStyle: String, CaseIterable, Identifiable {
    case rainbow
    case dark
    case mesh
    case classic
    case glass
    case light
    case nightTown
    case nineties
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .rainbow: return "Rainbow"
        case .dark: return "Dark"
        case .mesh: return "Mesh"
        case .classic: return "Classic"
        case .glass: return "Glass"
        case .light: return "Light"
        case .nightTown: return "Night Town"
        case .nineties: return "90s Party"
        }
    }
}

/// Shared background used by every privacy cover in the app.
struct PrivacyOverlayBackground: View {
    @AppStorage("privacyBackgroundStyle") private var style: PrivacyBackgroundStyle = .classic
    
    /// If true, this view is being used as the main app background (behind content).
    /// If false, it is being used as a privacy overlay (obscuring content).
    var asBackground: Bool = false

    var body: some View {
        Group {
            switch style {
            case .rainbow:
                LinearGradient(
                    colors: [.pink, .orange, .yellow, .green, .mint, .blue, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    Color.black.opacity(0.45)
                )
            case .dark:
                LinearGradient(
                    colors: [Color(white: 0.12), Color.black],
                    startPoint: .top,
                    endPoint: .bottom
                )
            case .mesh:
                ZStack {
                    Color.black
                    
                    // Blue/Purple orb
                    RadialGradient(
                        colors: [.blue.opacity(0.6), .clear],
                        center: .topLeading,
                        startRadius: 100,
                        endRadius: 600
                    )
                    
                    // Pink/Red orb
                    RadialGradient(
                        colors: [.pink.opacity(0.5), .clear],
                        center: .bottomTrailing,
                        startRadius: 100,
                        endRadius: 500
                    )
                    
                    // Cyan/Mint orb
                    RadialGradient(
                        colors: [.cyan.opacity(0.4), .clear],
                        center: .bottomLeading,
                        startRadius: 50,
                        endRadius: 400
                    )
                    
                    // Orange orb
                    RadialGradient(
                        colors: [.orange.opacity(0.3), .clear],
                        center: .topTrailing,
                        startRadius: 50,
                        endRadius: 400
                    )
                }
                .blur(radius: 60)
            case .classic:
                #if os(macOS)
                if asBackground {
                    Color.clear // Allow system window background to show
                } else {
                    WindowBackgroundView()
                }
                #else
                Color(uiColor: .systemBackground)
                #endif
            case .glass:
                ZStack {
                    // A subtle gradient to give it some "body" so it's not just the system background color
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.1),
                            Color.purple.opacity(0.05),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    
                    if asBackground {
                        #if os(macOS)
                        Rectangle().fill(.ultraThinMaterial)
                        #else
                        Rectangle().fill(.ultraThinMaterial)
                        #endif
                    } else {
                        #if os(macOS)
                        Rectangle().fill(.regularMaterial)
                        #else
                        Rectangle().fill(.regularMaterial)
                        #endif
                    }
                    
                    // Shine/Reflection
                    LinearGradient(
                        colors: [.white.opacity(0.15), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            case .light:
                Color(white: 0.95)
            case .nightTown:
                NightTownView()
            case .nineties:
                NinetiesPartyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

private struct NinetiesPartyView: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            // Psychedelic Background
            AngularGradient(gradient: Gradient(colors: [.red, .yellow, .green, .blue, .purple, .red]), center: .center)
                .rotationEffect(.degrees(animate ? 360 : 0))
                .scaleEffect(1.5)
            
            // Floating Shapes
            ForEach(0..<12) { i in
                NinetiesShape(index: i)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                animate = true
            }
        }
    }
}

struct NinetiesShape: View {
    let index: Int
    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 1
    @State private var position: CGPoint = .zero
    
    let shapes = ["triangle.fill", "circle.fill", "star.fill", "square.fill", "hexagon.fill"]
    let colors: [Color] = [.cyan, .mint, .pink, .yellow, .white]
    
    var body: some View {
        GeometryReader { proxy in
            Image(systemName: shapes[index % shapes.count])
                .font(.system(size: CGFloat.random(in: 30...60)))
                .foregroundStyle(colors[index % colors.count])
                .rotationEffect(.degrees(rotation))
                .scaleEffect(scale)
                .position(position)
                .onAppear {
                    // Initial random position
                    position = CGPoint(
                        x: CGFloat.random(in: 0...proxy.size.width),
                        y: CGFloat.random(in: 0...proxy.size.height)
                    )
                    
                    // Animate
                    withAnimation(
                        .easeInOut(duration: Double.random(in: 1...3))
                        .repeatForever(autoreverses: true)
                    ) {
                        scale = CGFloat.random(in: 0.5...1.5)
                        rotation = Double.random(in: 0...360)
                    }
                    
                    withAnimation(
                        .linear(duration: Double.random(in: 5...10))
                        .repeatForever(autoreverses: true)
                    ) {
                        position = CGPoint(
                            x: CGFloat.random(in: 0...proxy.size.width),
                            y: CGFloat.random(in: 0...proxy.size.height)
                        )
                    }
                }
        }
    }
}

private struct NightTownView: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 1. Deep Night Sky
                LinearGradient(
                    colors: [
                        Color(red: 0.02, green: 0.02, blue: 0.1), // Deep midnight blue
                        Color(red: 0.05, green: 0.05, blue: 0.2),
                        Color(red: 0.1, green: 0.1, blue: 0.3)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                // 2. Stars
                ForEach(0..<50) { i in
                    Circle()
                        .fill(Color.white.opacity(Double.random(in: 0.3...0.8)))
                        .frame(width: Double.random(in: 1...2), height: Double.random(in: 1...2))
                        .position(
                            x: Double.random(in: 0...geometry.size.width),
                            y: Double.random(in: 0...geometry.size.height * 0.6)
                        )
                }
                
                // 3. Distant Mountains (Silhouette)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geometry.size.height))
                    path.addLine(to: CGPoint(x: 0, y: geometry.size.height * 0.6))
                    path.addCurve(
                        to: CGPoint(x: geometry.size.width, y: geometry.size.height * 0.5),
                        control1: CGPoint(x: geometry.size.width * 0.3, y: geometry.size.height * 0.4),
                        control2: CGPoint(x: geometry.size.width * 0.7, y: geometry.size.height * 0.7)
                    )
                    path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.05, green: 0.05, blue: 0.15), Color.black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                
                // 4. Closer Hills/Town Base
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geometry.size.height))
                    path.addLine(to: CGPoint(x: 0, y: geometry.size.height * 0.7))
                    path.addCurve(
                        to: CGPoint(x: geometry.size.width, y: geometry.size.height * 0.8),
                        control1: CGPoint(x: geometry.size.width * 0.4, y: geometry.size.height * 0.85),
                        control2: CGPoint(x: geometry.size.width * 0.8, y: geometry.size.height * 0.65)
                    )
                    path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                    path.closeSubpath()
                }
                .fill(Color.black.opacity(0.8))
                
                // 5. Town Lights (The "Bokeh" effect)
                ForEach(0..<80) { i in
                    Circle()
                        .fill(
                            [Color.yellow, Color.orange, Color(red: 1.0, green: 0.9, blue: 0.8)]
                                .randomElement()!
                                .opacity(Double.random(in: 0.4...0.9))
                        )
                        .frame(width: Double.random(in: 2...4), height: Double.random(in: 2...4))
                        .shadow(color: .orange.opacity(0.5), radius: 2, x: 0, y: 0)
                        .position(
                            x: Double.random(in: 0...geometry.size.width),
                            y: Double.random(in: geometry.size.height * 0.65...geometry.size.height)
                        )
                }
                
                // 6. A few "streetlights" or brighter spots
                ForEach(0..<15) { i in
                    Circle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 2, height: 2)
                        .shadow(color: .white, radius: 4, x: 0, y: 0)
                        .position(
                            x: Double.random(in: 0...geometry.size.width),
                            y: Double.random(in: geometry.size.height * 0.7...geometry.size.height)
                        )
                }
            }
        }
    }
}

#if os(macOS)
private struct WindowBackgroundView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .windowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
    }
}
#endif

struct PrivacyCardBackground: ViewModifier {
    @AppStorage("privacyBackgroundStyle") private var style: PrivacyBackgroundStyle = .classic
    
    func body(content: Content) -> some View {
        content
            .background(
                Group {
                    switch style {
                    case .glass:
                        ZStack {
                            Color.white.opacity(0.05)
                            #if os(macOS)
                            Rectangle().fill(.ultraThinMaterial)
                            #else
                            Rectangle().fill(.ultraThinMaterial)
                            #endif
                            LinearGradient(
                                colors: [.white.opacity(0.25), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                    case .dark, .nightTown, .nineties:
                        Color.black.opacity(0.6)
                    case .light:
                        Color.white.opacity(0.8)
                    case .classic:
                        #if os(macOS)
                        Rectangle().fill(.ultraThinMaterial)
                        #else
                        Rectangle().fill(.ultraThinMaterial)
                        #endif
                    default:
                        #if os(macOS)
                        Rectangle().fill(.ultraThinMaterial)
                        #else
                        Rectangle().fill(.ultraThinMaterial)
                        #endif
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        style == .glass ? Color.white.opacity(0.3) : (style == .light ? Color.black.opacity(0.1) : Color.clear),
                        lineWidth: 1
                    )
            )
            .shadow(color: style == .glass ? Color.black.opacity(0.1) : (style == .light ? Color.black.opacity(0.05) : Color.clear), radius: 10, x: 0, y: 5)
    }
}

extension View {
    func privacyCardStyle() -> some View {
        modifier(PrivacyCardBackground())
    }
}
