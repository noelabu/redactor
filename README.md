# Redactor

A macOS menu bar app that takes a screenshot, blacks out personal information in it, and puts the redacted image on the clipboard. The unredacted image is never written to disk, and everything runs on the Mac.

Built for screenshots of Philippine documents (IDs, payslips, government forms, chats) as well as everyday screens.

## How it works

1. Press **⌘⌥⇧4** (or choose **Capture & Redact** from the menu bar icon) and select an area.
2. A preview opens straight away. Boxes from the rules appear in about half a second; the AI check adds more a few seconds later.
3. When detection finishes, the redacted image is copied to the clipboard.
4. In the preview, click a box to turn it off or on, or drag to add one. **Save** writes the image to your screenshot folder (Desktop by default) and copies it again. **Close** leaves only the clipboard copy.

**Review Last Capture…** reopens any of the last five captures, which are kept in memory only.

## What gets redacted

**Rules** (always on):
- Email addresses, phone numbers, street addresses and links
- Credit card numbers, checked with the Luhn checksum
- Philippine IDs: TIN, SSS, PhilHealth, Pag-IBIG, PhilSys (PSN), UMID CRN, passport and LTO driver's licence numbers
- Labelled form fields, in English or Tagalog, such as `Name:`, `Apelyido / Last Name`, `Date of Birth`, `Tirahan / Address`. The value is taken from the same line or from the box to the right or below. Names and birthdates are redacted only when they have a label.

**AI check** (needs Apple Intelligence): Apple's on-device model reads the text and reports names, birthdates, addresses, ID and account numbers the rules missed. It can only add boxes. Every value it reports is checked against the kind it claims to be and must actually appear on the page. The model doesn't support Filipino, so Filipino lines are skipped by the AI and covered by the rules only.

**Double-check:** after redacting, the app reads the redacted image again, up to twice, and boxes anything still readable.

## Privacy

- The capture goes to a private temp file that is deleted as soon as it is read. Leftover temp files are removed at launch.
- If redaction fails, nothing is saved or copied.
- Saved PNGs keep only image data, size, DPI and colour information. No metadata is written.
- Holding Control during selection makes macOS put the unredacted image on the clipboard; Redactor detects this and clears it.
- No network access. OCR (Vision) and the AI model both run on the Mac.

## Requirements

- macOS 26 or later
- Xcode 26 / Swift 6.2
- Apple Intelligence turned on, for the AI check (optional)

## Build and install

```sh
make install     # builds, signs and installs to ~/Applications, then launches
```

On first launch, grant **Screen Recording** in System Settings → Privacy & Security.

macOS ties the Screen Recording permission to the app's signature. `make install` first creates a self-signed "Redactor Local Signing" certificate in your login keychain (once), so the permission survives rebuilds. To stop codesign from asking for keychain access every build, run once:

```sh
security set-key-partition-list -S apple-tool:,apple: -s -l "Redactor Local Signing" ~/Library/Keychains/login.keychain-db
```

Other targets:

| Command | What it does |
|---|---|
| `make` | Run tests and build the app |
| `make test` | Run the test suite |
| `make app` | Build and sign `build/Redactor.app` |
| `make run` | Open the installed app |
| `make reset-tcc` | Reset the Screen Recording permission and reinstall |
| `make clean` | Remove build output |

## Tests

```sh
swift test
```

Opt-in suites:

```sh
REDACTOR_AI_EVAL=1 swift test --filter AIEvalTests                  # runs the real on-device model
REDACTOR_TIMING_IMAGE=/path/to.png swift test --filter TimingTests  # times each stage on an image
REDACTOR_DEBUG_OUT=/some/dir swift test --filter DebugRenderTests   # writes sample before/after images
```

## Layout

```
Sources/RedactorCore/   detection, OCR, box geometry, rendering, PNG output
Sources/Redactor/       menu bar app: hotkey, capture, preview window
Tests/RedactorCoreTests/
scripts/                signing certificate setup
build.sh                builds, signs and installs the .app bundle
```
