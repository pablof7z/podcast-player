import Foundation
@preconcurrency import NDKSwiftCore

/// Adapter between our value-type `SignedNostrEvent` (returned by
/// `NostrSigner.sign(_:)`) and NDKSwift's `NDKEvent` (consumed by
/// `NDK.publish(_:)`). Lets services keep the codable signer surface
/// while routing publishes through the shared relay pool instead of
/// opening transient WebSocket sockets.
enum NDKEventConverter {
    /// Build an `NDKEvent` from a signed wire-ready event. The signature
    /// and id are passed through unchanged — NDK does not re-canonicalise
    /// or re-sign. Use this immediately before `ndk.publish(event)`.
    static func toNDKEvent(_ event: SignedNostrEvent) -> NDKEvent {
        NDKEvent(
            id: event.id,
            pubkey: event.pubkey,
            createdAt: Timestamp(event.created_at),
            kind: event.kind,
            tags: event.tags,
            content: event.content,
            sig: event.sig
        )
    }
}
