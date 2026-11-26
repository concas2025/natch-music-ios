// MochyApp.swift
// Natch Music (iOS) — Native Swift / SwiftUI port based on Mochy Music (https://github.com/realidkroo/Mochy-Music, GPL-3.0).
// Built upon the foundations of Mochy Music, ViviMusic, Metrolist, InnerTune, Monochrome, AutoEq & GRDB.swift.

import Foundation
import MochyCore
import MochyDatabase
import MochyUI
import SwiftUI

@main
struct MochyApp: App {
    @State private var coordinator: AppCoordinator

    init() {
        let database: MochyDatabase
        do {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let dbPath = appSupport.appendingPathComponent("mochy_music.sqlite").path
            database = try MochyDatabase.open(path: dbPath)
        } catch {
            // Fall back cleanly to in-memory store if container initialization fails.
            database = try! MochyDatabase.inMemory()
        }
        let settings = AppSettings()
        _coordinator = State(initialValue: AppCoordinator(settings: settings, database: database))
    }

    var body: some Scene {
        WindowGroup {
            RootShellView(coordinator: coordinator)
        }
    }
}
