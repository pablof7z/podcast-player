//! Podcast-specific `ActionModule` registrations — identity namespace.
//!
//! The canonical NMP composition (NIP-02 / NIP-17 / NIP-57 / NIP-65 action
//! modules, routing substrate) is wired by
//! `nmp_app_template::register_defaults` in `register.rs`. This file adds the
//! **Podcast-specific** identity actions that drive the sign-in, sign-out,
//! account-switch, and profile-publish flows from Swift.
//!
//! ## Namespaces
//!
//! | Namespace                          | Wire shape                  | Actor command                    |
//! |------------------------------------|-----------------------------|---------------------------------|
//! | `podcast.identity.sign_in_nsec`    | `SignInNsecAction`          | `ActorCommand::SignInNsec`       |
//! | `podcast.identity.sign_in_bunker`  | `SignInBunkerAction`        | `ActorCommand::SignInBunker`     |
//! | `podcast.identity.sign_out`        | `SignOutAction`             | `ActorCommand::RemoveAccount`    |
//! | `podcast.identity.switch_account`  | `SwitchAccountAction`       | `ActorCommand::SwitchActive`     |
//! | `podcast.identity.publish_profile` | `PublishProfileAction`      | `ActorCommand::PublishProfile`   |
//!
//! ## Intentional omissions
//!
//! - **`cancel_bunker`** — not an `ActorCommand`; the broker is
//!   process-global (`GLOBAL_BROKER`). Swift calls the existing
//!   `nmp_app_cancel_bunker_handshake` C symbol directly, which routes
//!   through `nmp-signer-broker`'s `BunkerBroker::cancel`. Wrapping it
//!   behind an `ActionModule` would introduce a hidden dependency on the
//!   global singleton without cleaner guarantees. Document this for Swift
//!   callers in `NmpApp+Podcast.swift`.
//!
//! - **`edit_profile`** — no matching `ActorCommand` exists in `nmp-core`.
//!   Draft profile edits are Swift-side ephemeral state; only
//!   `publish_profile` crosses the FFI boundary (D4 — actor is the
//!   single writer of published identity facts).
//!
//! ## D6 — errors as state
//!
//! All execute bodies return `Ok(())` after enqueuing the `ActorCommand`; the
//! actor's identity dispatch arms own toast-visible error surfacing (bad nsec
//! hex, no active account, etc.). Semantic errors never cross the FFI as
//! panics or `Err`.

use nmp_core::ActorCommand;
use nmp_ffi::NmpApp;
use serde::{Deserialize, Serialize};
use zeroize::Zeroizing;

use nmp_core::substrate::ActionModule;

// ---------------------------------------------------------------------------
// Wire shapes
// ---------------------------------------------------------------------------

/// Wire shape for `podcast.identity.sign_in_nsec` —
/// `{"secret":"<nsec-or-hex-privkey>"}`.
///
/// The `secret` field is held in a [`Zeroizing<String>`] so the plaintext is
/// wiped from memory as soon as the command is dispatched to the actor thread.
/// Mirrors `ActorCommand::SignInNsec`'s `Zeroizing` contract.
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct SignInNsecAction {
    /// nsec (bech32) or hex private key supplied by the user.
    /// The actor validates format; shape-only decode here (D6).
    pub secret: String,
}

/// Wire shape for `podcast.identity.sign_in_bunker` —
/// `{"uri":"bunker://<pubkey>?relay=...&secret=..."}`.
///
/// The actor forwards the URI to the registered bunker hook
/// (`nmp-signer-broker`) which owns the handshake state machine.
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct SignInBunkerAction {
    /// Full `bunker://` or `nostrconnect://` URI.
    pub uri: String,
}

/// Wire shape for `podcast.identity.sign_out` —
/// `{"identity_id":"<hex-pubkey>"}`.
///
/// Removes the named account. If it was the active account the kernel clears
/// the active slot; Swift should navigate to the onboarding flow on the next
/// snapshot tick that arrives with `active_account: null`.
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct SignOutAction {
    /// Hex pubkey of the account to remove.
    pub identity_id: String,
}

/// Wire shape for `podcast.identity.switch_account` —
/// `{"identity_id":"<hex-pubkey>"}`.
///
/// Switches the active signer to the named account and retargets the
/// subscription cluster. The timeline re-targets on the next tick.
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct SwitchAccountAction {
    /// Hex pubkey of the account to activate.
    pub identity_id: String,
}

/// Wire shape for `podcast.identity.publish_profile` —
/// `{"fields":{"name":"…","about":"…","picture":"…",…}}`.
///
/// `fields` is a flat JSON object of NIP-01 kind:0 metadata keys. The actor
/// serialises it into the kind:0 `content`, stamps `created_at`, signs, and
/// routes through the NIP-65 outbox. Unknown keys are forwarded verbatim (the
/// actor never strips fields it does not recognise — forward-compat).
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct PublishProfileAction {
    /// Free-form NIP-01 kind:0 metadata fields (name, about, picture, …).
    pub fields: serde_json::Map<String, serde_json::Value>,
}

// ---------------------------------------------------------------------------
// ActionModule impls
// ---------------------------------------------------------------------------

/// `podcast.identity.sign_in_nsec` — import an nsec / hex secret as a local
/// account and make it active.
///
/// The `secret` is wrapped in `Zeroizing` before handing it to the actor so
/// the plaintext occupies memory for the shortest possible window. Shape
/// validation (bech32 / hex check) is the actor's responsibility (D6).
pub struct SignInNsecModule;

impl ActionModule for SignInNsecModule {
    const NAMESPACE: &'static str = "podcast.identity.sign_in_nsec";
    type Action = SignInNsecAction;

    fn execute(
        action: Self::Action,
        _correlation_id: &str,
        send: &dyn Fn(ActorCommand),
    ) -> Result<(), String> {
        send(ActorCommand::SignInNsec {
            secret: Zeroizing::new(action.secret),
        });
        Ok(())
    }
}

/// `podcast.identity.sign_in_bunker` — parse a `bunker://` URI and initiate a
/// NIP-46 handshake via the registered broker.
///
/// The actor's `SignInBunker` arm forwards the URI to the broker hook (wired
/// by `nmp_signer_broker_init`). `cancel_bunker` is deliberately not an
/// action — see module doc.
pub struct SignInBunkerModule;

impl ActionModule for SignInBunkerModule {
    const NAMESPACE: &'static str = "podcast.identity.sign_in_bunker";
    type Action = SignInBunkerAction;

    fn execute(
        action: Self::Action,
        _correlation_id: &str,
        send: &dyn Fn(ActorCommand),
    ) -> Result<(), String> {
        send(ActorCommand::SignInBunker { uri: action.uri });
        Ok(())
    }
}

/// `podcast.identity.sign_out` — remove an account by its hex pubkey.
///
/// If the removed account was the active one the kernel clears the active slot.
/// The next snapshot tick will have `active_account: null` and
/// `nip46_onboarding.is_signed_out: true`.
pub struct SignOutModule;

impl ActionModule for SignOutModule {
    const NAMESPACE: &'static str = "podcast.identity.sign_out";
    type Action = SignOutAction;

    fn execute(
        action: Self::Action,
        _correlation_id: &str,
        send: &dyn Fn(ActorCommand),
    ) -> Result<(), String> {
        send(ActorCommand::RemoveAccount {
            identity_id: action.identity_id,
        });
        Ok(())
    }
}

/// `podcast.identity.switch_account` — switch the active signer and retarget
/// the subscription cluster.
pub struct SwitchAccountModule;

impl ActionModule for SwitchAccountModule {
    const NAMESPACE: &'static str = "podcast.identity.switch_account";
    type Action = SwitchAccountAction;

    fn execute(
        action: Self::Action,
        _correlation_id: &str,
        send: &dyn Fn(ActorCommand),
    ) -> Result<(), String> {
        send(ActorCommand::SwitchActive {
            identity_id: action.identity_id,
        });
        Ok(())
    }
}

/// `podcast.identity.publish_profile` — sign and publish a kind:0 metadata
/// event for the active account.
///
/// `correlation_id` is threaded through so the publish engine reports the
/// action's id in `action_results` when the signed event reaches its terminal
/// state (accepted or rejected by the outbox).
pub struct PublishProfileModule;

impl ActionModule for PublishProfileModule {
    const NAMESPACE: &'static str = "podcast.identity.publish_profile";
    type Action = PublishProfileAction;

    fn execute(
        action: Self::Action,
        correlation_id: &str,
        send: &dyn Fn(ActorCommand),
    ) -> Result<(), String> {
        send(ActorCommand::PublishProfile {
            fields: action.fields,
            correlation_id: Some(correlation_id.to_string()),
        });
        Ok(())
    }
}

// ---------------------------------------------------------------------------
// Registration helper
// ---------------------------------------------------------------------------

/// Register all Podcast identity `ActionModule`s against `app`'s action
/// registry. Called from [`super::register::nmp_app_podcast_register`] after
/// `nmp_app_template::register_defaults`.
///
/// `register_action` requires `&mut NmpApp` so this must be called before
/// `nmp_app_start`. Registering the same namespace twice is a programming
/// error (the second registration would shadow the first); production init
/// paths call this once.
pub fn register_identity_actions(app: &mut NmpApp) {
    app.register_action::<SignInNsecModule>();
    app.register_action::<SignInBunkerModule>();
    app.register_action::<SignOutModule>();
    app.register_action::<SwitchAccountModule>();
    app.register_action::<PublishProfileModule>();
}

// ---------------------------------------------------------------------------
// Unit tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use std::cell::RefCell;

    use super::*;

    #[test]
    fn namespace_prefix_is_podcast() {
        assert!(SignInNsecModule::NAMESPACE.starts_with("podcast.identity."));
        assert!(SignInBunkerModule::NAMESPACE.starts_with("podcast.identity."));
        assert!(SignOutModule::NAMESPACE.starts_with("podcast.identity."));
        assert!(SwitchAccountModule::NAMESPACE.starts_with("podcast.identity."));
        assert!(PublishProfileModule::NAMESPACE.starts_with("podcast.identity."));
    }

    #[test]
    fn sign_in_nsec_enqueues_command() {
        let action = SignInNsecAction {
            secret: "nsec1testkey".to_string(),
        };
        // `ActionModule::execute` takes `&dyn Fn(ActorCommand)` — use `RefCell`
        // for interior mutability inside the `Fn` closure.
        let commands: RefCell<Vec<ActorCommand>> = RefCell::new(Vec::new());
        let result =
            SignInNsecModule::execute(action, "corr-1", &|cmd| commands.borrow_mut().push(cmd));
        assert!(result.is_ok());
        let commands = commands.into_inner();
        assert_eq!(commands.len(), 1);
        match &commands[0] {
            ActorCommand::SignInNsec { secret } => {
                assert_eq!(secret.as_str(), "nsec1testkey");
            }
            _ => panic!("expected SignInNsec"),
        }
    }

    #[test]
    fn sign_in_bunker_enqueues_command() {
        let action = SignInBunkerAction {
            uri: "bunker://pubkey?relay=wss://r.example".to_string(),
        };
        let commands: RefCell<Vec<ActorCommand>> = RefCell::new(Vec::new());
        let result = SignInBunkerModule::execute(action, "corr-2", &|cmd| {
            commands.borrow_mut().push(cmd)
        });
        assert!(result.is_ok());
        let commands = commands.into_inner();
        assert_eq!(commands.len(), 1);
        match &commands[0] {
            ActorCommand::SignInBunker { uri } => {
                assert!(uri.starts_with("bunker://"));
            }
            _ => panic!("expected SignInBunker"),
        }
    }

    #[test]
    fn sign_out_enqueues_remove_account() {
        let action = SignOutAction {
            identity_id: "deadbeef".repeat(8),
        };
        let commands: RefCell<Vec<ActorCommand>> = RefCell::new(Vec::new());
        let result = SignOutModule::execute(action.clone(), "corr-3", &|cmd| {
            commands.borrow_mut().push(cmd)
        });
        assert!(result.is_ok());
        let commands = commands.into_inner();
        match &commands[0] {
            ActorCommand::RemoveAccount { identity_id } => {
                assert_eq!(*identity_id, action.identity_id);
            }
            _ => panic!("expected RemoveAccount"),
        }
    }

    #[test]
    fn switch_account_enqueues_switch_active() {
        let action = SwitchAccountAction {
            identity_id: "cafebabe".repeat(8),
        };
        let commands: RefCell<Vec<ActorCommand>> = RefCell::new(Vec::new());
        let result = SwitchAccountModule::execute(action.clone(), "corr-4", &|cmd| {
            commands.borrow_mut().push(cmd)
        });
        assert!(result.is_ok());
        let commands = commands.into_inner();
        match &commands[0] {
            ActorCommand::SwitchActive { identity_id } => {
                assert_eq!(*identity_id, action.identity_id);
            }
            _ => panic!("expected SwitchActive"),
        }
    }

    #[test]
    fn publish_profile_threads_correlation_id() {
        let mut fields = serde_json::Map::new();
        fields.insert(
            "name".to_string(),
            serde_json::Value::String("Alice".to_string()),
        );
        let action = PublishProfileAction { fields };
        let commands: RefCell<Vec<ActorCommand>> = RefCell::new(Vec::new());
        let result = PublishProfileModule::execute(action, "corr-5", &|cmd| {
            commands.borrow_mut().push(cmd)
        });
        assert!(result.is_ok());
        let commands = commands.into_inner();
        match &commands[0] {
            ActorCommand::PublishProfile {
                correlation_id,
                fields,
            } => {
                assert_eq!(correlation_id.as_deref(), Some("corr-5"));
                assert_eq!(
                    fields.get("name").and_then(|v| v.as_str()),
                    Some("Alice")
                );
            }
            _ => panic!("expected PublishProfile"),
        }
    }
}
