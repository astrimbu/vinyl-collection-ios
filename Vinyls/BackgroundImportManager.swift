import Foundation
import SwiftUI

@MainActor
class BackgroundImportManager: ObservableObject {
    static let shared = BackgroundImportManager()
    
    @Published var isImporting: Bool = false
    @Published var total: Int = 0
    @Published var completed: Int = 0
    
    var progress: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
    
    func start(total: Int) {
        self.total = total
        self.completed = 0
        self.isImporting = total > 0
    }
    
    func increment() {
        guard total > 0 else { return }
        if completed < total { completed += 1 }
        if completed >= total { isImporting = false }
    }
    
    func finish() {
        if total > 0 { completed = total }
        isImporting = false
    }
}


