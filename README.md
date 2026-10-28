<div align="center">

# Redactor

**Screenshot or copy anything. Personal info is removed before it ever reaches your clipboard.**

A macOS menu bar app for screenshots and copied text from IDs, payslips, forms, chats, logs and config — built with Philippine documents in mind. Everything runs on your Mac.

![macOS 26+](https://img.shields.io/badge/macOS-26%2B-black?logo=apple)
![Swift 6.2](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white)
![On-device](https://img.shields.io/badge/processing-on--device-2ea44f)
![No network](https://img.shields.io/badge/network-none-2ea44f)

<img src="docs/images/form.png" alt="An employee information sheet before and after Redactor: name, birthdate, TIN, SSS, PhilHealth, address, mobile and email are blacked out; position and department are left alone." width="900">

</div>

## Why

A screenshot is the fastest way to share what's on your screen, and the easiest way to leak someone's TIN, birthday or phone number. Redactor replaces the macOS screenshot shortcut with one that finds that information and boxes it before you paste, and does the same for text you copy.

<p align="center">
  <img src="docs/images/chat.png" alt="A chat before and after Redactor: the contact's name, TIN, mobile number and email are blacked out; the rest of the conversation is untouched." width="820">
</p>

## How it works

```mermaid
flowchart LR
    A["⌘⌥⇧4<br/>select an area"] --> B["Read the text<br/>(Vision OCR)"]
    B --> C["Rules<br/>IDs · emails · phones<br/>addresses · labelled fields"]
    C --> D["AI check<br/>Apple on-device model"]
    D --> E["Double-check<br/>re-read the redacted image"]
    E --> F["📋 Clipboard"]
    F -. "Save" .-> G["💾 Screenshot folder"]
```

1. Press **⌘⌥⇧4** (or **Capture & Redact** in the menu bar) and select an area.
2. The preview opens right away. Boxes from the rules show up in about half a second; the AI check adds more a few seconds later. The menu bar icon turns into an hourglass while it works.
3. The redacted image is copied to your clipboard. Nothing is written to disk.
4. In the preview, **click** a box to turn it off or on, or **drag** to add one. **Save** writes the image to your screenshot folder and copies the edited version. **Close** keeps just the clipboard copy.

**Review Last Capture…** in the menu reopens any of the last five captures. They live in memory only and are gone when you quit.

## Copied text

While Redactor is running, text you copy is redacted automatically. Each value becomes a numbered placeholder, and the same value gets the same placeholder throughout the copy:

```
Copied:  Hi team, doc 8812 fails for Juan Dela Cruz (TIN 123-456-789-000), juan.dc@gmail.com
Pasted:  Hi team, doc 8812 fails for [NAME 1] (TIN [ID 1]), [EMAIL 1]
```

```mermaid
flowchart LR
    A["Copy text"] --> B["Rules<br/>under 0.1 s"]
    B --> C["📋 Clipboard"]
    B --> D["AI check<br/>1–3 s"]
    D -. "if nothing new was copied" .-> C
```

1. The rules' version replaces the clipboard within a quarter of a second.
2. The AI check runs next and, if it finds more, replaces the clipboard again, unless you've copied something else in the meantime.
3. A banner says how many items were redacted. **Restore original** on the banner, or **Restore Last Copy** in the menu, puts the original back.

| Placeholder | For |
|---|---|
| `[NAME n]` `[BIRTHDATE n]` `[ADDRESS n]` | Personal details |
| `[ID n]` `[CARD n]` | Government IDs, account and card numbers |
| `[EMAIL n]` `[PHONE n]` | Contact details |
| `[SECRET n]` | API keys, tokens, passwords |

Links are kept so shared links still work; personal info inside a link (`?email=…`) is still redacted. Copying text that's already redacted changes nothing.

**Skipped:** copies from password managers (they mark them concealed), apps you exclude with **Exclude &lt;app&gt;** in the menu, files and images, and anything copied before launch or while **Redact Copied Text** is off. Copies over 10,000 characters skip the AI check; copies over a million characters are left alone, with a banner.

## What gets redacted

| | Examples |
|---|---|
| **Philippine IDs** | TIN, SSS, PhilHealth, Pag-IBIG, PhilSys (PSN), UMID CRN, passport, LTO driver's licence |
| **Contact details** | Email addresses, phone numbers, street addresses, links |
| **Cards** | Credit and debit card numbers (Luhn-checked) |
| **Labelled form fields** | `Name:`, `Date of Birth`, `Apelyido / Last Name`, `Tirahan / Address`, … in English or Tagalog — the value next to or below the label |
| **Secrets** | OpenAI, Anthropic, AWS, GitHub, Slack, Google and Stripe keys, JWTs, `Bearer` tokens, private keys, the password in `postgres://user:pass@host` |
| **Code and config keys** | `"full_name": "…"`, `firstName: …`, `date_of_birth=…`, `DB_PASSWORD=…`, `?email=…` — JSON, YAML, `.env`, logs and URLs |
| **AI check** | Names, birthdates, addresses and account numbers the rules missed |

Names and birthdates are redacted by the rules only when they have a label, so a document date or a company name isn't blacked out by mistake.

### The AI check

When Apple Intelligence is on, Apple's on-device language model reads the text as a second opinion. It can only **add** boxes, never remove one, and every value it reports must look like what it claims to be (a name has no digits, a birthdate is in the past, an ID has enough digits) and must actually appear on the page. The model doesn't support Filipino, so Filipino lines are covered by the rules only. If Apple Intelligence is off, the preview says so and the rules still run.

### The double-check

After the first pass, Redactor reads the **redacted** image again, up to twice, and boxes anything a detector can still read.

## Privacy

- 🔒 **The original is never saved.** The capture goes to a private temp file that is deleted as soon as it's read, and leftovers are cleaned up at launch.
- 🚫 **Fails closed.** If redaction fails, nothing is copied or saved.
- 🧾 **No metadata.** Saved PNGs keep only pixels, size, DPI and colour profile.
- 📋 **Clipboard guard.** Holding Control during selection makes macOS copy the unredacted image; Redactor notices and clears it.
- 📡 **No network.** OCR and the AI model both run on your Mac.
- 📝 **Plain text only.** Redacted text replaces every format on the clipboard, so the original's rich text or HTML copy doesn't survive.
- 🧠 **Copied originals stay in memory**, for Restore, until your next copy. If checking copied text fails, the clipboard is cleared.

### Known limits

- Clipboard managers (Raycast, Paste, Alfred) and Universal Clipboard see what you copy before Redactor does. Exclude sensitive apps there, or turn Handoff off, if that matters.
- A paste within about a quarter of a second of copying, or before the AI check finishes, can carry the earlier version.
- The AI check skips Filipino lines; the rules still cover them.
- Restore brings back plain text, not the original formatting.

## Install

Requires macOS 26 and Xcode 26 (Swift 6.2). Apple Intelligence is optional, for the AI check.

```sh
git clone https://github.com/noelabu/redactor.git
cd redactor
make install
```

This builds the app, signs it, copies it to `~/Applications` and launches it. On first launch, allow **Screen Recording** in System Settings → Privacy & Security.

<details>
<summary><b>Why a signing certificate?</b></summary>

macOS ties the Screen Recording permission to the app's signature. `make install` creates a self-signed "Redactor Local Signing" certificate in your login keychain once, so the permission survives rebuilds. To stop codesign asking for keychain access on every build, run this once (it asks for your login password):

```sh
security set-key-partition-list -S apple-tool:,apple: -s -l "Redactor Local Signing" ~/Library/Keychains/login.keychain-db
```

</details>

<details>
<summary><b>All make targets</b></summary>

| Command | What it does |
|---|---|
| `make` | Run tests and build the app |
| `make test` | Run the test suite |
| `make app` | Build and sign `build/Redactor.app` |
| `make install` | Build, sign, install to `~/Applications` and launch |
| `make run` | Open the installed app |
| `make reset-tcc` | Reset the Screen Recording permission and reinstall |
| `make clean` | Remove build output |

</details>

## Development

```sh
swift test
```

Opt-in suites:

```sh
REDACTOR_AI_EVAL=1 swift test --filter AIEvalTests                         # real on-device model: recall and false hits
REDACTOR_TIMING_IMAGE=/path/to.png swift test --filter TimingTests         # time each stage on an image
REDACTOR_README_OUT=$PWD/docs/images swift test --filter ReadmeImageTests  # regenerate the images in this README
```

The README images are drawn from made-up data and redacted by the real engine.

```
Sources/RedactorCore/   detection, OCR, text redaction, box geometry, rendering, PNG output
Sources/Redactor/       menu bar app: hotkey, capture, preview window, clipboard watcher
Tests/RedactorCoreTests/
scripts/                signing certificate setup
build.sh                builds, signs and installs the .app bundle
```
