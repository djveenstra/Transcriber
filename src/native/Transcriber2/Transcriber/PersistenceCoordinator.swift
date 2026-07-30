import SwiftData

/// The save seam used by processing orchestration.
///
/// The caller still owns mutation order and user-facing failure handling. This
/// collaborator only performs the existing `ModelContext.save()` operation.
@MainActor
protocol PersistenceCoordinating {
    func save(_ context: ModelContext) throws
}

@MainActor
struct ModelContextPersistenceCoordinator: PersistenceCoordinating {
    func save(_ context: ModelContext) throws {
        try context.save()
    }
}

@MainActor
struct ClosurePersistenceCoordinator: PersistenceCoordinating {
    let saveContext: (ModelContext) throws -> Void

    func save(_ context: ModelContext) throws {
        try saveContext(context)
    }
}
