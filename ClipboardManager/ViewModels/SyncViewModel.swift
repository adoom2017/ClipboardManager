import SwiftUI
import Combine

class SyncViewModel: ObservableObject {
    @Published var discoveredPeers: [DiscoveredPeer] = []

    private var cancellables = Set<AnyCancellable>()
    private let service = SyncService.shared

    init() {
        service.$discoveredPeers
            .receive(on: DispatchQueue.main)
            .assign(to: &$discoveredPeers)
    }
}
