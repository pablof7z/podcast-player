# Plan: Pod0 Nostr Publishing Migration from NIP-74 to NIP-F4

Canonical status: tracked from `docs/plan.md` and `docs/BACKLOG.md`.

## Context

The app currently publishes podcast feeds using NIP-74 (`kind:30074` show, `kind:30075` episode) — parameterised replaceable events where a single agent key signs all podcasts, distinguished by `d` tags.

NIP-F4 (`F4.md` on the `podcasts` branch of nostr-protocol/nips) redesigns this around per-podcast keypairs:
- Each podcast IS its own Nostr identity (keypair)
- Show metadata: `kind:10154` replaceable event signed by the podcast key
- Episodes: `kind:54` regular events signed by the podcast key
- Agent claims ownership via `kind:10064` replaceable event listing all podcast pubkeys

Key consequence: no `d` tags on either event; shows are identified by pubkey alone; episodes are discovered by filtering `kind:54` authored by the podcast pubkey.

---

## Event Structure Mapping

| Concept | NIP-74 (old) | NIP-F4 (new) |
|---|---|---|
| Show | `kind:30074`, d-tag: `podcast:guid:<uuid>` | `kind:10154`, no d-tag |
| Episode | `kind:30075`, d-tag: `podcast:item:guid:<uuid>` | `kind:54`, no d-tag |
| Author claim | — | `kind:10064` from agent key |
| Show description tag | `summary` | `description` |
| Episode audio | `imeta url … m … x … size …` | `["audio", "<url>", "<mime>"]` |
| Episode-to-show link | `a` tag on episode | implicit: same podcast pubkey |
| Show coordinate | `30074:<agent-pubkey>:<d-tag>` | `10154:<podcast-pubkey>` |
| Signer for show/episode | agent key | per-podcast key |

Episode `content` field: markdown show notes (same value as description for now).

---

## New: `PodcastKeyStore.swift`

New file: `App/Sources/Services/PodcastKeyStore.swift`

Stores per-podcast private keys in Keychain, keyed by podcast UUID.

```swift
enum PodcastKeyStore {
    static func savePrivateKey(_ hex: String, podcastID: UUID) throws
    static func privateKey(podcastID: UUID) throws -> String?
    static func deletePrivateKey(podcastID: UUID) throws
    // Keychain account: "podcast-privkey-<uuid-lowercased>"
    // Keychain service: same as NostrCredentialStore.service
}
```

Key generation in `LiveAgentOwnedPodcastManager` when a podcast is first published:
```swift
// If no key stored yet, generate one and save it
if try PodcastKeyStore.privateKey(podcastID: podcast.id) == nil {
    let generated = try NDKPrivateKeySigner.generate()
    try PodcastKeyStore.savePrivateKey(generated.privateKeyHex, podcastID: podcast.id)
}
let privkey = try PodcastKeyStore.privateKey(podcastID: podcast.id)!
let podcastSigner = try LocalKeySigner(privateKeyHex: privkey)
```

`podcast.ownerPubkeyHex` stores the **podcast's** pubkey (derived from the podcast key), not the agent's pubkey. This is set on first publish and stored on the `Podcast` model.

---

## Changes: `NostrPodcastPublisher.swift`

**`publishShow(podcast:signer:)`**
- Kind: `30074` → `10154`
- Remove `["d", ...]` tag
- Tag `summary` → `description`
- Keep `title`, `image`, `language`, `t`, `p` tags
- `p` tag uses the podcast pubkey (from `signer.publicKey()`)

**`publishEpisode(episode:podcast:audioURL:audioData:chaptersURL:transcriptURL:signer:)`**
- Kind: `30075` → `54`
- Remove `["d", ...]` tag
- Remove `["a", "30074:..."]` tag (no more show reference)
- Remove `published_at` tag (use `created_at`)
- Replace `imeta` block with: `["audio", audioURL.absoluteString, "audio/mp4"]`
- Keep `title`, `image`, `description`, `duration`, `chapters`, `transcript` tags
- Set `content` = episode description (markdown)

**Add `publishAuthorClaim(podcastPubkeys:[String], agentSigner:)`**
- Kind: `10064` (replaceable, no d-tag)
- Tags: one `["p", podcastPubkey]` per owned podcast
- Signed by the **agent** key
- Called after any create/update to keep the claim list current

**Remove** the `publisher: any NostrEventPublishing` init parameter (already vestigial).

---

## Changes: `NostrPodcastDiscoveryService.swift`

**Wire constants:**
```swift
static let kindShow = 10154
static let kindEpisode = 54
```

**`ShowResult`:** remove `dTag` field; `coordinate` = `"10154:<pubkey>"`.

**`fetchShows()`:** filter `kinds: [10154]`; coordinate = `"10154:\(pubkey)"`.

**`fetchEpisodes(for:relayURL:podcastID:)`:**
- Filter: `authors: [show.pubkey], kinds: [54]` — no `a` tag filter needed
- Dedup by event `id` (no d-tag; each episode is a unique event)

**`podcastID(for:)`:** unchanged in logic; coordinate now `"10154:<pubkey>"` → still produces a stable UUID.

**`parseShow(from:)`:**
- No d-tag parsing; use `pubkey` as sole identifier
- `summary` tag → `description` tag (fall back to content)

**`parseEpisode(from:podcastID:)`:**
- Audio: parse `["audio", url, mime?]` tag instead of `imeta`
- guid: use `event.id` (hex)
- Description: `description` tag, fall back to `content`
- Remove `published_at` — use `event.createdAt` for `pubDate`

**`subscribe(to:store:relayURL:)`:** no d-tag reference; coordinate = `"10154:\(show.pubkey)"`.

---

## Changes: `LiveAgentOwnedPodcastManager.swift`

**`createPodcast()`:**
1. If `visibility == .public`: generate podcast keypair via `PodcastKeyStore`, derive podcast pubkey
2. Set `ownerPubkeyHex` = podcast pubkey (not agent pubkey)
3. After publishing show, also call `publishAuthorClaim()` with agent signer

**`publishShowEvent(podcast:settings:)`:**
- Retrieve/generate podcast private key from `PodcastKeyStore`
- Create `podcastSigner = LocalKeySigner(privateKeyHex: podcastPrivkey)`
- Pass `podcastSigner` to `publisher.publishShow()`
- Call `publisher.publishAuthorClaim(podcastPubkeys: allOwnedPubkeys, agentSigner: agentSigner)`

**`publishEpisodeRecord(_:podcast:settings:)`:**
- Retrieve podcast private key from `PodcastKeyStore`
- Pass `podcastSigner` to all `blossom.upload` calls and `publisher.publishEpisode`

**`nostrAddr(for:eventID:)`:**
- kind:10154 is a regular replaceable event — no naddr (which is for parameterised replaceable 30000-39999)
- Return `NIP19.npub(pubkeyHex: podcastPubkeyHex)` or the pubkey hex directly
- Update `AgentOwnedPodcastInfo.nostrAddr` comment accordingly

**`publishEpisodeToNostr(episodeID:)`:**
- Remove the naddr construction (no d-tag); return event ID directly

**`deletePodcast()`:**
- Call `PodcastKeyStore.deletePrivateKey(podcastID:)` to clean up stored key

---

## Changes: `Podcast.swift`

Comments only:
- `nostrVisibility`: update reference from NIP-74 kinds to NIP-F4 kinds (10154/54)
- `nostrCoordinate`: update format description to `"10154:<podcast-pubkey-hex>"`
- `ownerPubkeyHex`: clarify it now stores the podcast's own pubkey (not the agent's)

---

## Files NOT changed

- `Episode.swift` — no Nostr-specific fields
- `KeychainStore.swift` — reused as-is by PodcastKeyStore
- `NIP19.swift` — npub encoding already exists
- `NostrStack.swift`, `NIP65RelayFetcher.swift` — unchanged
- `NostrDiscoverForm.swift` — no kind numbers; queries through the service

---

## Verification

1. **Build**: no compile errors (kind numbers are `Int` literals, tag names are `String` — no type changes required beyond removing d-tag parameters)
2. **Publish a new podcast**: confirm `kind:10154` event published to relay with correct tags (no d-tag, `description` present)
3. **Publish an episode**: confirm `kind:54` event with `["audio", url, mime]` tag and no `a`/`d` tags
4. **Discover via NostrDiscoverForm**: confirm shows loaded from `kind:10154` events; episodes fetched by author pubkey
5. **Author claim**: confirm `kind:10064` event published from agent key after create/update
6. **Delete podcast**: confirm `PodcastKeyStore` key removed from Keychain
