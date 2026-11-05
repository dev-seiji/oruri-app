import SwiftUI
import Combine

/// Substituto de `@State` que não depende do plugin de macro `SwiftUIMacros`.
/// No SDK atual `@State` é uma macro, e o plugin só vem com o Xcode completo;
/// com apenas as Command Line Tools o projeto não compilaria.
final class StateBox<Value>: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    var value: Value {
        willSet { objectWillChange.send() }
    }
    init(_ value: Value) { self.value = value }
}

@propertyWrapper
struct LocalState<Value>: DynamicProperty {
    @StateObject private var box: StateBox<Value>

    init(wrappedValue: Value) {
        _box = StateObject(wrappedValue: StateBox(wrappedValue))
    }

    var wrappedValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue }
    }

    var projectedValue: Binding<Value> {
        let box = box
        return Binding(get: { box.value }, set: { box.value = $0 })
    }
}
