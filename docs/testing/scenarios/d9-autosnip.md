# Scenario D9: AutoSnip (auto-clip last 30 seconds)

## Goal
Validate the AutoSnip transport button captures a 30-second clip ending at the
current playback moment, and that it surfaces in Clippings.

## Prerequisites
- App past onboarding, an episode playing (ideally one with a transcript so the clip
  has context).

## Steps
1. Start playback and let it run past 0:30. *Screenshot.*
2. Tap the **AutoSnip** button (bookmark.fill, accessibility label "Snip last 30
   seconds"). **Expected:** An AutoSnipBanner appears (e.g., "Clipped: <title>").
   *Screenshot.*
3. Open the **Clippings** tab. **Expected:** A new clip appears at the top
   ("just now") with a 30-second range ending at the snip moment. *Screenshot.*
4. Inspect the clip's source badge. **Expected:** No "Auto/Agent" badge for a manual
   touch snip; an automatic snip shows the "Auto" sparkles badge. *Screenshot.*
5. (If no LLM key) verify a NoLLMKeyHintBanner appears hinting that context naming
   needs a provider. *Screenshot.*

## Acceptance Criteria
- Tapping AutoSnip creates a clip ending at the current moment, ~30s long.
- The clip appears in the Clippings tab promptly.
- The banner confirms the snip.
- Source badge reflects the capture source (touch vs auto vs agent).

## Known Issues / Watch Points
- Without an LLM key, the clip may lack an AI-generated caption — the
  NoLLMKeyHintBanner is the expected signal, not a FAIL.
- AutoSnip is also reachable via headphone/AirPods gestures (not testable in sim).

## Notes

**Result: BLOCKED**
**Tested: 2026-06-24, ~3:44 PM**

Steps executed:
- Step 1: PASS — Started playback of "R.F.K. Jr.'s Newest Mission..." at position 8:46, let it play to 8:59 (past 30 seconds). Playback working correctly.
- Step 2: PARTIAL — Tapped AutoSnip button (e219, bookmark.fill icon) successfully, but no visual confirmation banner appeared on screen.
- Step 3-5: BLOCKED — Unable to navigate to Clippings tab to verify clip creation.

**Blocking Issue:**
The sidebar navigation (accessed via avatar/profile button at top-left) does not open despite multiple tap attempts. Per RootView.swift code (lines 5-8), "Clippings are reachable from the avatar sidebar" and the TabView tabs are hidden via `.toolbar(.hidden, for: .tabBar)`. Without functional sidebar access, cannot navigate to Clippings to verify:
- Clip appears in the list
- Clip has ~30-second range ending at snip moment
- Source badge reflects manual touch (no "Auto" badge expected)
- NoLLMKeyHintBanner appears (if no LLM key configured)

**Next Steps:**
- Investigate why sidebar button tap is not triggering state change (showSidebar = true)
- Consider alternative navigation for testing (direct TabView selection if exposed)
- Verify app state in simulator is functioning normally for other features
