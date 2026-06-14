//! OPML 2.0 subscription list import and export. Ports
//! `OPMLImport.swift` and `OPMLExport.swift`.

pub mod export;
pub mod import;

pub use export::{export_opml, export_opml_with};
pub use import::{
    import_opml, import_opml_report, OpmlError, OpmlImportIssue, OpmlImportReport, MAX_OPML_BYTES,
    MAX_OPML_FEEDS,
};
