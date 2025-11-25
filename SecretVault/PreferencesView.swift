import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var vaultManager: VaultManager
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

            Divider()

            Text("Security")
                .font(.headline)

            Toggle("Secure Deletion (Overwrite)", isOn: $vaultManager.secureDeletionEnabled)
            Text("When enabled, deleted files are overwritten 3 times. This is slower but more secure. Disable for instant deletion.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 360, minHeight: 250)
        .onChange(of: vaultManager.secureDeletionEnabled) { _ in
            vaultManager.saveSettings()
        }
    }
}

struct PreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesView()
            .environmentObject(VaultManager.shared)
    }
}
