# Note sharing

Open a note and tap the share button in its toolbar. The sheet offers a public link, local text sharing, and a Markdown export with notes, flashcards, and quiz answers. All three use native iOS ShareLink sheets. Copy Link writes only to the local device clipboard, not Universal Clipboard.

Public sharing loads current server state each time the sheet opens or the app returns to the foreground. A failed read or ambiguous write does not expose an old link or pretend sharing is disabled. Enable requires a completed note and an explicit tap after the privacy warning. The disable-link control is deliberately hidden until web PR #4 deployment is verified. Exported copies cannot be revoked. Exports use in-memory Transferable data instead of leaving private Markdown files in the temporary directory.

## Backend contract

Verified in `koboshchan/terribly-made-notes-app` main `b46b920` and PR #4 head `261812f` on October 14, 2026.

| Action | Request | Response |
| --- | --- | --- |
| Read | GET `/api/notes/{id}/share` | `shareUrl` or null |
| Enable | POST `/api/notes/{id}/share`, JSON `{"allowChat":false}` | `shareUrl` |
| Disable | DELETE `/api/notes/{id}/share` | success, null `shareUrl` |

GET and POST exist on main. DELETE requires the web PR #4 backend to be deployed. The iOS PR does not deploy that backend. At Lucas’s request, no disable-link control or revocation instructions are shown in the shipping UI until deployment is verified. The internal DELETE client and model tests remain ready for that later change. Old servers return an explicit unsupported-operation error and the iOS app does not claim revocation succeeded. Do not release this as full enable/disable support until the backend update is live.

The decoder also accepts PR #4's `shareEnabled`, `shareExpiresAt`, and `shareAllowChat`. URL-only responses from main remain compatible. Expired, explicitly disabled, non-HTTPS, and credential-bearing URLs are not offered. AI chat is off on newly created links. Existing links with chat enabled show an account-usage warning; there is no implicit update of their permissions when opening the sheet.

## Verification

Generate the Xcode project with XcodeGen. Run the `NotesSharingTests` scheme. Unit tests cover response compatibility, expiry and unsafe URL rejection, authoritative loading, enable/disable, duplicate write prevention, failure recovery, and Markdown data. The separate `NotesSharingHost` target exercises the real sharing views with a fixture-only API. It never links into Notes, does not bypass production sign-in, and makes no network requests.

UI tests cover light/dark, create/copy and absence of revocation controls, read failure, and native link/text/Markdown sheets. They attach screenshots to the xcresult. The fixture links are not live public notes. Live authenticated backend mutation is intentionally not performed by these tests.

Verified on October 14, 2026 with a successful unsigned iOS Release build, 8 passing unit tests, and 5 passing UI tests on the iPhone 17 Pro simulator. Final light/dark, failure, and native share-sheet screenshots were inspected. The final 1206×2622 dark screenshot measures URL and status glyph interiors at RGB (142, 142, 143) against card RGB (28, 28, 30), giving 5.1984:1 using sRGB relative luminance, above WCAG AA 4.5:1. No text-style change was needed. Native preview artwork/extension availability remains simulator-dependent; this does not establish physical-device export delivery.
