import SwiftUI

/// Sdílený stav, zda je popover otevřený — `FreshnessDot` animuje jen když ano
/// (jistota, že po zavření popoveru pulzující animace neběží = nešetří baterii nadarmo).
@MainActor
final class PopoverVisibility: ObservableObject {
    @Published var isOpen: Bool = false
}
