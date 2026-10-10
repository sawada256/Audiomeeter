import Combine

/// Meter frames invalidate meter views, rather than every mixer control.
final class MixerMeterStore: ObservableObject {
    struct Frame {
        var strips: [StripID: MeterLevel] = [:]
        var buses: [BusID: MeterLevel] = [:]
    }
    @Published var frame = Frame()
    func level(_ target: InsertTarget) -> MeterLevel {
        switch target {
        case .strip(let strip): return frame.strips[strip] ?? MeterLevel()
        case .bus(let bus): return frame.buses[bus] ?? MeterLevel()
        }
    }
}
