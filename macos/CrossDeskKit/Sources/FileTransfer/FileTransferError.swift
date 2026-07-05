import Foundation

public enum FileTransferError: Error, Equatable {
    /// Path from the wire violates §8 (absolute, `..`, NUL, empty component)
    /// or would escape the staging directory.
    case unsafePath(String)
    /// Message arrived in a state that does not accept it (DATA without an
    /// open file, ITEM_META before the previous ITEM_DONE, anything after
    /// TRANSFER_DONE…).
    case unexpectedMessage
    /// ITEM_DONE arrived before `size` bytes did, or the source file shrank
    /// while being read.
    case sizeMismatch(path: String)
    /// SHA-256 of the received bytes differs from the sender's.
    case hashMismatch(path: String)
    /// More DATA than the declared item size.
    case overflow(path: String)
    /// `materialize` called before TRANSFER_DONE.
    case incompleteTransfer
}
