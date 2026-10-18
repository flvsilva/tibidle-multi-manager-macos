public enum TabOrder {
    /// Moves `account` to the position currently held by `targetAccount`.
    public static func move(_ order: inout [Int], account: Int, onto targetAccount: Int) {
        guard let from = order.firstIndex(of: account),
              let to = order.firstIndex(of: targetAccount), from != to else { return }
        order.remove(at: from)
        order.insert(account, at: to)
    }
}
