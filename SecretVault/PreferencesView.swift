import SwiftUI

struct PreferencesView: View {
    @AppStorage("undoTimeoutSeconds") private var undoTimeoutSeconds: Double = 5.0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("General")
                .font(.headline)

            HStack {
                Text("Undo banner timeout")
                Spacer()
                Text("\(Int(undoTimeoutSeconds))s")
                    .foregroundStyle(.secondary)
            }

            Slider(value: $undoTimeoutSeconds, in: 2...20, step: 1)

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 360, minHeight: 120)
    }
}

struct PreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesView()
    }
}
