import Foundation

public struct ApplicationRecord: Equatable, Sendable {
    public let id: Int32
    public let persistenceID: String
    public let name: String
    public let isHidden: Bool
    public let isRegular: Bool

    public init(id: Int32, persistenceID: String, name: String,
                isHidden: Bool = false, isRegular: Bool = true) {
        self.id = id
        self.persistenceID = persistenceID
        self.name = name
        self.isHidden = isHidden
        self.isRegular = isRegular
    }
}

/// Tracks applications, including hidden ones, so hiding never destroys recency.
public struct ApplicationHistory {
    public private(set) var records: [ApplicationRecord] = []
    public private(set) var order: [Int32] = []
    public private(set) var rememberedOrder: [String]
    private let excludedID: Int32

    public init(excludedID: Int32, rememberedOrder: [String] = []) {
        self.excludedID = excludedID
        var seen: Set<String> = []
        self.rememberedOrder = Array(rememberedOrder.filter { seen.insert($0).inserted }.prefix(256))
    }

    public mutating func update(_ newRecords: [ApplicationRecord]) {
        records = newRecords.filter { $0.isRegular && $0.id != excludedID && $0.id > 0 }
        let runningIDs = Set(records.map(\.id))
        order.removeAll { !runningIDs.contains($0) }
        let known = Set(order)
        let rememberedRanks = Dictionary(rememberedOrder.enumerated().map { ($1, $0) },
                                         uniquingKeysWith: { first, _ in first })
        let newApps = records.filter { !known.contains($0.id) }.sorted {
            let left = rememberedRanks[$0.persistenceID] ?? Int.max
            let right = rememberedRanks[$1.persistenceID] ?? Int.max
            if left != right { return left < right }
            let nameOrder = $0.name.localizedStandardCompare($1.name)
            return nameOrder == .orderedSame ? $0.id < $1.id : nameOrder == .orderedAscending
        }
        order.append(contentsOf: newApps.map(\.id))
    }

    public mutating func activate(_ id: Int32) {
        guard let record = records.first(where: { $0.id == id }) else { return }
        order.removeAll { $0 == id }
        order.insert(id, at: 0)
        rememberedOrder.removeAll { $0 == record.persistenceID }
        rememberedOrder.insert(record.persistenceID, at: 0)
        rememberedOrder = Array(rememberedOrder.prefix(256))
    }

    public var visible: [ApplicationRecord] {
        let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return order.compactMap { byID[$0] }.filter { !$0.isHidden }
    }
}

/// The list freezes while cycling; updates remove missing apps without reshuffling it.
public struct SwitcherSession: Equatable, Sendable {
    public private(set) var ids: [Int32]
    public private(set) var selectedIndex: Int
    public var selectedID: Int32? { ids.indices.contains(selectedIndex) ? ids[selectedIndex] : nil }

    public init(ids: [Int32], currentID: Int32?, backwards: Bool = false) {
        self.ids = ids
        selectedIndex = 0
        guard !ids.isEmpty else { return }
        if let currentID, let index = ids.firstIndex(of: currentID) {
            selectedIndex = index
            advance(backwards ? -1 : 1)
        } else {
            // The foreground application may itself be hidden or an accessory.
            selectedIndex = backwards ? ids.count - 1 : 0
        }
    }

    public mutating func advance(_ offset: Int) {
        guard !ids.isEmpty else { return }
        selectedIndex = ((selectedIndex + offset) % ids.count + ids.count) % ids.count
    }

    public mutating func select(_ id: Int32) {
        if let index = ids.firstIndex(of: id) { selectedIndex = index }
    }

    public mutating func reconcile(visibleIDs: [Int32]) {
        let previousSelection = selectedID
        let visible = Set(visibleIDs)
        let oldIDs = ids
        let oldIndex = selectedIndex
        // Keep the successor in the original circular order if selection disappeared.
        let successor = oldIDs.isEmpty ? nil : (1...oldIDs.count).lazy
            .map { oldIDs[(oldIndex + $0) % oldIDs.count] }.first { visible.contains($0) }
        ids.removeAll { !visible.contains($0) }
        let existing = Set(ids)
        ids.append(contentsOf: visibleIDs.filter { !existing.contains($0) })
        if let selected = previousSelection, let index = ids.firstIndex(of: selected) {
            selectedIndex = index
        } else if let successor, let index = ids.firstIndex(of: successor) {
            selectedIndex = index
        } else {
            selectedIndex = min(selectedIndex, max(0, ids.count - 1))
        }
    }
}

/// Keeps each swallowed key-down paired with its key-up, even after cancellation.
public struct KeyOwnership {
    private var held: Set<UInt16> = []
    public init() {}
    public mutating func consumeDown(_ key: UInt16) { held.insert(key) }
    public mutating func consumeUp(_ key: UInt16) -> Bool { held.remove(key) != nil }
    public mutating func reset() { held.removeAll() }
}
