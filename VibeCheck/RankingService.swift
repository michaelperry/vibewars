import Foundation
import CloudKit
import CryptoKit

actor RankingService {

    static let shared = RankingService()

    private let container = CKContainer(identifier: "iCloud.com.michaelperry.VibeCheck")
    private let database: CKDatabase

    private init() {
        self.database = container.publicCloudDatabase
    }

    // MARK: - Submit Score

    /// Submit (or update) the user's anonymous score for a given period.
    /// The user's CloudKit ID is hashed before use so records can't be
    /// correlated back to an iCloud account, even by querying the public DB.
    func submitScore(_ score: Double, periodType: String, periodKey: String) async throws {
        let userID = try await container.userRecordID()
        let anonymousID = hashedID(userID.recordName)
        let recordID = CKRecord.ID(recordName: "\(anonymousID)_\(periodType)_\(periodKey)")

        // Try to fetch existing record to update, otherwise create new
        let record: CKRecord
        do {
            record = try await database.record(for: recordID)
            record["vibeScore"] = score as CKRecordValue
            record["modifiedAt"] = Date() as CKRecordValue
        } catch {
            let newRecord = CKRecord(recordType: "ScoreEntry", recordID: recordID)
            newRecord["vibeScore"] = score as CKRecordValue
            newRecord["periodType"] = periodType as CKRecordValue
            newRecord["periodKey"] = periodKey as CKRecordValue
            newRecord["modifiedAt"] = Date() as CKRecordValue
            record = newRecord
        }

        let _ = try await database.save(record)
    }

    // MARK: - Fetch Ranking

    /// Fetch the user's rank and percentile for a given period.
    func fetchRanking(myScore: Double, periodType: String, periodKey: String) async throws -> (rank: Int, total: Int, percentile: Double) {
        // Count records with score higher than ours
        let abovePredicate = NSPredicate(format: "periodType == %@ AND periodKey == %@ AND vibeScore > %f", periodType, periodKey, myScore)
        let aboveQuery = CKQuery(recordType: "ScoreEntry", predicate: abovePredicate)
        let aboveCount = try await countRecords(matching: aboveQuery)

        // Count total records for this period
        let totalPredicate = NSPredicate(format: "periodType == %@ AND periodKey == %@", periodType, periodKey)
        let totalQuery = CKQuery(recordType: "ScoreEntry", predicate: totalPredicate)
        let totalCount = try await countRecords(matching: totalQuery)

        let rank = aboveCount + 1
        let percentile = totalCount > 1
            ? Double(totalCount - rank) / Double(totalCount - 1) * 100.0
            : 100.0

        return (rank, totalCount, percentile)
    }

    // MARK: - Helpers

    private func countRecords(matching query: CKQuery) async throws -> Int {
        var count = 0
        let operation = CKQueryOperation(query: query)
        operation.desiredKeys = [] // We only need the count, not field data
        operation.resultsLimit = CKQueryOperation.maximumResults

        let (results, _) = try await database.records(matching: query, resultsLimit: CKQueryOperation.maximumResults)
        count = results.count
        return count
    }

    // MARK: - Privacy

    /// One-way hash of the CloudKit user record name so the raw iCloud
    /// identifier never appears in public database records.
    private func hashedID(_ recordName: String) -> String {
        let salt = "vibecheck_2026" // static salt to namespace the hash
        let input = Data((salt + recordName).utf8)
        let digest = SHA256.hash(data: input)
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Account Status

    func isAvailable() async -> Bool {
        do {
            let status = try await container.accountStatus()
            return status == .available
        } catch {
            return false
        }
    }
}
