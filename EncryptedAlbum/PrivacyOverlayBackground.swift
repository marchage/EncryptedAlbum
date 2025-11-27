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
    case webOne
    case bh90210
    
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
        case .webOne: return "Web 1.0"
        case .bh90210: return "BH 90210"
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
            case .webOne:
                WebOneView()
            case .bh90210:
                BH90210View()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

private struct WebOneView: View {
    var body: some View {
        VStack(spacing: 0) {
            // 1. Title Bar
            HStack {
                Text("Netscape Navigator")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.leading, 4)
                Spacer()
            }
            .frame(height: 24)
            .background(Color(red: 0.0, green: 0.0, blue: 0.5)) // Classic dark blue
            
            // 2. Menu Bar
            HStack(spacing: 12) {
                ForEach(["File", "Edit", "View", "Go", "Bookmarks", "Options", "Directory", "Help"], id: \.self) { menu in
                    Text(menu)
                        .font(.system(size: 12))
                        .foregroundStyle(.black)
                }
                Spacer()
            }
            .padding(.horizontal, 4)
            .frame(height: 24)
            .background(Color(white: 0.75))
            
            // 3. Toolbar
            HStack(spacing: 4) {
                Group {
                    NetscapeToolbarButton(icon: "arrow.backward", label: "Back")
                    NetscapeToolbarButton(icon: "arrow.forward", label: "Forward")
                    NetscapeToolbarButton(icon: "house", label: "Home")
                    NetscapeToolbarButton(icon: "arrow.clockwise", label: "Reload")
                    NetscapeToolbarButton(icon: "photo", label: "Images")
                    NetscapeToolbarButton(icon: "folder", label: "Open")
                    NetscapeToolbarButton(icon: "printer", label: "Print")
                    NetscapeToolbarButton(icon: "magnifyingglass", label: "Find")
                    NetscapeToolbarButton(icon: "hand.raised.fill", label: "Stop")
                }
                
                Spacer()
                
                // The Big N Logo
                ZStack {
                    Rectangle()
                        .fill(Color(white: 0.75))
                        .frame(width: 44, height: 44)
                        .classicBevel()
                    
                    Text("N")
                        .font(.system(size: 36, weight: .bold, design: .serif))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .black.opacity(0.5), radius: 1, x: 2, y: 2)
                        .overlay(
                            // Simple "shooting star" animation effect
                            ShootingStarOverlay()
                        )
                }
                .padding(.trailing, 4)
            }
            .padding(4)
            .background(Color(white: 0.75))
            
            // 4. Location Bar
            HStack(spacing: 4) {
                Text("Location:")
                    .font(.system(size: 12))
                    .foregroundStyle(.black)
                
                HStack {
                    Text("about:blank")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.black)
                    Spacer()
                }
                .padding(4)
                .background(Color.white)
                .classicBevel(reversed: true)
            }
            .padding(6)
            .background(Color(white: 0.75))
            
            // 5. Content Area
            ZStack {
                Color(white: 0.75).ignoresSafeArea()
                
                VStack(spacing: 20) {
                    Spacer()
                    
                    Text("Netscape Navigator™")
                        .font(.system(size: 32, weight: .bold, design: .serif))
                        .foregroundStyle(.black)
                    
                    Text("version 1.0N")
                        .font(.system(size: 18, weight: .bold, design: .serif))
                        .foregroundStyle(.black)
                    
                    VStack(spacing: 4) {
                        Text("Copyright © 1994 Netscape Communications Corporation,")
                        Text("All rights reserved.")
                    }
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(.black)
                    
                    Divider()
                        .background(Color.gray)
                        .padding(.horizontal, 40)
                    
                    Text("This software is subject to the license agreement set forth in the LICENSE file.")
                        .font(.system(size: 12, design: .serif))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .foregroundStyle(.black)
                    
                    Text("Report any problems to win_debug@mcom.com")
                        .font(.system(size: 12, design: .serif))
                        .underline()
                        .foregroundStyle(.blue)
                        .padding(.top, 10)
                    
                    Spacer()
                }
            }
            .classicBevel(reversed: true)
            .padding(4)
            .background(Color(white: 0.75))
        }
        .background(Color(white: 0.75))
    }
}

struct ShootingStarOverlay: View {
    @State private var animate = false
    
    var body: some View {
        GeometryReader { geo in
            Circle()
                .fill(Color.white)
                .frame(width: 4, height: 4)
                .position(x: animate ? geo.size.width : 0, y: animate ? geo.size.height : 0)
                .opacity(animate ? 0 : 1)
                .onAppear {
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        animate = true
                    }
                }
        }
    }
}

struct NetscapeToolbarButton: View {
    let icon: String
    let label: String
    
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.black)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.black)
        }
        .frame(width: 55, height: 45)
        .background(Color(white: 0.75))
        .classicBevel()
    }
}

extension View {
    func classicBevel(reversed: Bool = false) -> some View {
        self.overlay(
            GeometryReader { geo in
                ZStack {
                    // Top/Left Light
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: geo.size.height))
                        path.addLine(to: CGPoint(x: 0, y: 0))
                        path.addLine(to: CGPoint(x: geo.size.width, y: 0))
                    }
                    .stroke(reversed ? Color.gray : Color.white, lineWidth: 2)
                    
                    // Bottom/Right Dark
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: geo.size.height))
                        path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                        path.addLine(to: CGPoint(x: geo.size.width, y: 0))
                    }
                    .stroke(reversed ? Color.white : Color.gray, lineWidth: 2)
                }
            }
        )
    }
}

private struct BH90210View: View {
    var body: some View {
        ZStack {
            // Grid Background
            Color(white: 0.95).ignoresSafeArea()
            
            GeometryReader { geometry in
                Path { path in
                    let spacing: CGFloat = 40
                    for x in stride(from: 0, to: geometry.size.width, by: spacing) {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                    }
                    for y in stride(from: 0, to: geometry.size.height, by: spacing) {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                }
                .stroke(Color.black.opacity(0.1), lineWidth: 1)
            }
            
            // Memphis Shapes
            GeometryReader { geometry in
                ForEach(0..<15) { i in
                    MemphisShape(index: i)
                }
            }
        }
    }
}

struct MemphisShape: View {
    let index: Int
    @State private var rotation: Double = 0
    @State private var position: CGPoint = .zero
    
    // Memphis Palette
    let colors: [Color] = [
        Color(red: 0.2, green: 0.8, blue: 0.7), // Teal
        Color(red: 0.9, green: 0.4, blue: 0.6), // Pink
        Color(red: 1.0, green: 0.8, blue: 0.2), // Yellow
        Color(red: 0.4, green: 0.3, blue: 0.8)  // Purple
    ]
    
    var body: some View {
        Group {
            if index % 3 == 0 {
                // Triangle
                Image(systemName: "triangle.fill")
            } else if index % 3 == 1 {
                // Circle
                Circle()
            } else {
                // Squiggle (using bolt as approximation)
                Image(systemName: "bolt.fill")
            }
        }
        .frame(width: 50, height: 50)
        .foregroundStyle(colors[index % colors.count])
        .rotationEffect(.degrees(rotation))
        .shadow(color: .black.opacity(0.2), radius: 4, x: 4, y: 4)
        .position(position)
        .onAppear {
            // Random placement
            position = CGPoint(
                x: CGFloat.random(in: 0...500), // Approximate screen width
                y: CGFloat.random(in: 0...800)  // Approximate screen height
            )
            
            // Static rotation
            rotation = Double.random(in: 0...360)
        }
    }
}

private struct NinetiesPartyView: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            // 1. Tiled Background (Classic Web Grey Texture)
            Color(white: 0.75).ignoresSafeArea()
            
            GeometryReader { geometry in
                // 2. Random "GIF" elements
                ForEach(0..<15) { i in
                    NinetiesGifElement(index: i, containerSize: geometry.size)
                }
            }
            
            // 3. Main "Shocking" Content
            VStack(spacing: 60) {
                // Marquee-style Text
                Text("★ WELCOME ★")
                    .font(.custom("Times New Roman", size: 48))
                    .fontWeight(.black)
                    .foregroundStyle(.blue)
                    .shadow(color: .yellow, radius: 0, x: 4, y: 4)
                    .offset(x: animate ? 150 : -150)
                    .animation(.linear(duration: 2.0).repeatForever(autoreverses: true), value: animate)
                
                HStack(spacing: 50) {
                    // Flashing "NEW!" Star
                    ZStack {
                        Image(systemName: "seal.fill")
                            .font(.system(size: 100))
                            .foregroundStyle(.red)
                        Text("NEW!")
                            .font(.system(size: 24, weight: .bold, design: .serif))
                            .foregroundStyle(.yellow)
                            .rotationEffect(.degrees(-15))
                    }
                    .scaleEffect(animate ? 1.1 : 0.9)
                    .rotationEffect(.degrees(animate ? 10 : -10))
                    .animation(.easeInOut(duration: 0.15).repeatForever(autoreverses: true), value: animate)
                    
                    // "Cool" Graphic
                    Image(systemName: "sunglasses.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.black)
                        .background(Circle().fill(Color.yellow))
                        .offset(y: animate ? -20 : 20)
                        .animation(.interpolatingSpring(stiffness: 300, damping: 2).repeatForever(autoreverses: true), value: animate)
                }
                
                // Scrolling Text Bar
                Text("!!! UNDER CONSTRUCTION !!!")
                    .font(.system(.title, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding()
                    .background(Color.black)
                    .offset(x: animate ? -100 : 100)
                    .animation(.linear(duration: 0.8).repeatForever(autoreverses: true), value: animate)
            }
        }
        .onAppear {
            animate = true
        }
    }
}

struct NinetiesGifElement: View {
    let index: Int
    let containerSize: CGSize
    @State private var position: CGPoint = .zero
    @State private var isVisible = true
    
    let icons = ["flame.fill", "bolt.fill", "star.fill", "heart.fill", "envelope.fill"]
    let colors: [Color] = [.red, .yellow, .blue, .green, .purple]
    
    var body: some View {
        Image(systemName: icons[index % icons.count])
            .font(.system(size: 40))
            .foregroundStyle(colors[index % colors.count])
            .position(position)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                position = CGPoint(
                    x: CGFloat.random(in: 0...containerSize.width),
                    y: CGFloat.random(in: 0...containerSize.height)
                )
                
                // Blink animation
                withAnimation(
                    .easeInOut(duration: Double.random(in: 0.1...0.5))
                    .repeatForever(autoreverses: true)
                ) {
                    isVisible.toggle()
                }
                
                // Jitter movement
                withAnimation(
                    .linear(duration: Double.random(in: 0.2...0.5))
                    .repeatForever(autoreverses: true)
                ) {
                    position.x += CGFloat.random(in: -20...20)
                    position.y += CGFloat.random(in: -20...20)
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
                    case .dark, .nightTown, .nineties, .webOne:
                        Color.black.opacity(0.6)
                    case .light, .bh90210:
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
