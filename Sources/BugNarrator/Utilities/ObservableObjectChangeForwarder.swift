import Combine

@MainActor
final class ObservableObjectChangeForwarder {
    private var cancellables = Set<AnyCancellable>()

    func forward(_ publishers: [ObservableObjectPublisher], notify: @escaping () -> Void) {
        cancellables.removeAll()

        for publisher in publishers {
            publisher
                .sink { _ in
                    notify()
                }
                .store(in: &cancellables)
        }
    }
}
