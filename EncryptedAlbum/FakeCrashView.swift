import SwiftUI

struct FakeCrashView: View {
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.gray)
                
                Text("System Error")
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                
                Text("A critical error has occurred.\nThe application has been terminated to protect system integrity.")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                Text("Error Code: 0xDEADBEEF")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.gray.opacity(0.7))
                    .padding(.top, 10)
                
                Spacer()
            }
        }
        #if os(iOS)
        .statusBar(hidden: true)
        #endif
    }
}

#Preview {
    FakeCrashView()
}
