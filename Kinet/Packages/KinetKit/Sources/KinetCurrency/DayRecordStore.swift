import SwiftData

@MainActor
public final class DayRecordStore<Record: PersistentModel> {
    private let context: ModelContext
    private let dayID: (Record) -> String
    private let fetchOne: (String) -> FetchDescriptor<Record>
    private let fetchMany: ([String]) -> FetchDescriptor<Record>
    private var cache: [String: Record] = [:]

    public init(
        context: ModelContext,
        dayID: @escaping (Record) -> String,
        fetchOne: @escaping (String) -> FetchDescriptor<Record>,
        fetchMany: @escaping ([String]) -> FetchDescriptor<Record>
    ) {
        self.context = context
        self.dayID = dayID
        self.fetchOne = fetchOne
        self.fetchMany = fetchMany
    }

    public func preload(_ ids: [String]) {
        let missing = ids.filter { cache[$0] == nil }
        guard !missing.isEmpty else { return }
        for record in (try? context.fetch(fetchMany(missing))) ?? [] { cache[dayID(record)] = record }
    }

    public func record(for id: String, make: () -> Record) -> Record {
        if let cached = cache[id] { return cached }
        var descriptor = fetchOne(id)
        descriptor.fetchLimit = 1
        let record: Record
        if let existing = try? context.fetch(descriptor).first {
            record = existing
        } else {
            record = make()
            context.insert(record)
        }
        cache[id] = record
        return record
    }
}

public extension ModelContext {
    func saveIfNeeded() {
        guard hasChanges else { return }
        try? save()
    }
}
