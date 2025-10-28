//
//  VinylsApp.swift
//  Vinyls
//

import SwiftUI

@main
struct VinylsApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .onOpenURL { url in
                    DiscogsAuthService.shared.handleOpenURL(url)
                }
        }
    }
}
