import SwiftUI

struct AlbumView: View {
    // ...existing properties...
    @State private var showSettings = false

    var body: some View {
        NavigationView {
            List {
                // ...existing list content...
            }
            .navigationTitle("Albums")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        // ...existing menu items...
                        Button(action: {
                            showSettings = true
                        }) {
                            Label("Settings", systemImage: "gear")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }
}