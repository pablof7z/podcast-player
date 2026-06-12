//! Type manifest — the source-of-truth for the Swift Decodable structs.
//!
//! Each entry here corresponds directly to a Rust struct in
//! `apps/nmp-app-podcast/src/ffi/projections/` or a related source file.
//! Update BOTH the Rust struct AND the manifest entry here when the wire
//! shape changes; the CI drift gate will catch any divergence.

/// How the Swift field value is expressed in the `init(from:)` decoder.
#[derive(Clone, Debug)]
pub enum DecodeStrategy {
    /// `try c.decode(T.self, forKey: .x)` — required field, always present.
    Required,
    /// `try c.decodeIfPresent(T.self, forKey: .x)` — optional, decodes nil.
    Optional,
    /// `try c.decodeIfPresent(T.self, forKey: .x) ?? default` — omitted when default.
    WithDefault(String),
}

/// A single field in a Swift struct.
#[derive(Clone, Debug)]
pub struct Field {
    /// Swift camelCase field name (also the `CodingKeys` case name).
    pub name: &'static str,
    /// Swift type as it appears in the struct body, e.g. `"String"`, `"Int?"`, `"[EpisodeSummary]"`.
    pub swift_type: &'static str,
    /// Default value in the struct declaration, e.g. `"nil"`, `"[]"`, `"false"`, `"0"`.
    /// `None` means the field is a required `let`-style var with no default (the type must be non-optional).
    pub struct_default: Option<&'static str>,
    /// How to emit the decode expression.
    pub decode: DecodeStrategy,
    /// Optional property wrapper, e.g. `"@DefaultFalse"`, `"@DefaultEmptyArray"`.
    pub wrapper: Option<&'static str>,
    /// Optional doc comment line(s) (without `///` prefix).
    pub doc: Option<&'static str>,
}

impl Field {
    pub const fn required(name: &'static str, swift_type: &'static str) -> Self {
        Self { name, swift_type, struct_default: None, decode: DecodeStrategy::Required, wrapper: None, doc: None }
    }
    pub const fn opt(name: &'static str, swift_type: &'static str) -> Self {
        Self { name, swift_type, struct_default: Some("nil"), decode: DecodeStrategy::Optional, wrapper: None, doc: None }
    }
    pub fn default_val(name: &'static str, swift_type: &'static str, default: &'static str) -> Self {
        Self { name, swift_type, struct_default: Some(default), decode: DecodeStrategy::WithDefault(default.to_string()), wrapper: None, doc: None }
    }
    pub fn default_false(name: &'static str) -> Self {
        Self { name, swift_type: "Bool", struct_default: Some("false"), decode: DecodeStrategy::WithDefault("false".to_string()), wrapper: Some("@DefaultFalse"), doc: None }
    }
    pub fn default_empty_array(name: &'static str, elem_type: &'static str) -> Self {
        let swift_type = Box::leak(format!("[{elem_type}]").into_boxed_str());
        Self {
            name,
            swift_type,
            struct_default: Some("[]"),
            decode: DecodeStrategy::WithDefault("[]".to_string()),
            wrapper: Some("@DefaultEmptyArray"),
            doc: None,
        }
    }
    pub fn default_empty_strings(name: &'static str) -> Self {
        Self {
            name,
            swift_type: "[String]",
            struct_default: Some("[]"),
            decode: DecodeStrategy::WithDefault("[]".to_string()),
            wrapper: Some("@DefaultEmptyStrings"),
            doc: None,
        }
    }
    pub fn with_doc(mut self, doc: &'static str) -> Self {
        self.doc = Some(doc);
        self
    }
}

/// Protocol conformances for a struct.
#[derive(Clone, Debug)]
pub struct Conformances {
    pub identifiable: bool,
    pub equatable: bool,
    pub hashable: bool,
    /// If `identifiable`, the computed property that provides `id`.
    pub id_expr: Option<&'static str>,
}

impl Conformances {
    pub const EQUATABLE: Self = Self { identifiable: false, equatable: true, hashable: false, id_expr: None };
    pub const EQUATABLE_HASHABLE: Self = Self { identifiable: false, equatable: true, hashable: true, id_expr: None };
    pub fn identifiable(id_expr: &'static str) -> Self {
        Self { identifiable: true, equatable: true, hashable: true, id_expr: Some(id_expr) }
    }
    pub const NONE: Self = Self { identifiable: false, equatable: false, hashable: false, id_expr: None };
}

/// Whether the struct gets a hand-written `Codable` extension or a synthesized one.
pub enum CodableKind {
    /// Emit a custom `extension Foo: Codable { init(from:) ... }` block.
    Custom,
    /// The struct already has `Codable` in the protocol list (synthesized).
    Synthesized,
    /// No Codable at all (struct declaration only, extension added manually
    /// or from another source file).
    None,
}

/// A complete struct to emit.
pub struct Struct {
    pub name: &'static str,
    /// Extra protocols beyond auto-selected ones.
    pub extra_protos: &'static [&'static str],
    pub conformances: Conformances,
    pub codable_kind: CodableKind,
    pub fields: Vec<Field>,
    pub doc: Option<&'static str>,
}
