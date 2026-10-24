import Foundation

@MainActor
public protocol DayCloseParticipant: AnyObject {
    var closeOrder: Int { get }
    func prepare(days: [DayKey]) async
    func close(day: DayKey, in wallet: Wallet)
}
