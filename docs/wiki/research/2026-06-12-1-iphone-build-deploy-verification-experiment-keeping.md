---
type: research-record
date: 2026-06-12
session: 713480e4-3c98-439e-a897-2f41d37acbfd
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-podcast-player/713480e4-3c98-439e-a897-2f41d37acbfd.jsonl
source_lines: 89-112
agent_attribution: aa1d6379e725ba612
has_preregistered_criteria: true
has_method: true
has_structured_report: true
characterization: "iPhone build/deploy verification experiment: keeping Rust dylib (not deleting) eliminates duplicate-symbol linker errors, dylib embedded with @rpath and codesigned, app confirmed alive at 14 seconds — verdict ALIVE"
captured_at: 2026-06-12T13:27:50Z
---

iPhone build/deploy verification experiment: keeping Rust dylib (not deleting) eliminates duplicate-symbol linker errors, dylib embedded with @rpath and codesigned, app confirmed alive at 14 seconds — verdict ALIVE

---

User: [Tool result]: The app is alive and staying running. Here is the full report:

---

BUILD RESULT: BUILD SUCCEEDED

No duplicate-symbol errors. The "Fix Rust Dylib Install Name" and "Embed Rust Dylib" build phases ran as expected per the xcodebuild output.

PACKAGING CHECKS:

- Dylib embedded: `libnmp_app_podcast.dylib` is present in `Podcastr.app/Frameworks/`
- @rpath correct: `otool -L Podcastr.debug.dylib` shows `@rpath/libnmp_app_podcast.dylib` — no absolute `/Users/...` path
- Codesign: passed with "Apple Development: Pablo Fernandez (C99QRJCR43)"

INSTALL RESULT: Success

- Bundle ID `io.f7z.podcast` installed to `file:///private/var/containers/Bundle/Application/9AB7872C-3CBF-48EF-868A-432A1032AEE6/Podcastr.app/`

ALIVE VERDICT: ALIVE — confirmed running

- Process `Podcastr` (pid 8368) confirmed running at 6 seconds after launch
- Process still running at 14 seconds after launch
- Widget extension also running (pid 8362)
- No dyld/early crash — the process did not exit within the observa
