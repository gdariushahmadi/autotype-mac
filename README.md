# AutoType

<div dir="rtl">

**ورودی فارسی بدون عوض کردن چیدمان صفحه‌کلید.**

روی مک، برای نوشتن فارسی معمولاً باید چیدمان صفحه‌کلید را بین انگلیسی و فارسی عوض کنید.
AutoType این کار را حذف می‌کند: شما همیشه با چیدمان انگلیسی تایپ می‌کنید و هر کلمه‌ای که
فارسی باشد، خودکار به فارسی تبدیل می‌شود — دقیقاً مثل Diyar روی ویندوز.

- `sghl` → **سلام**
- `;jhf` → **کتاب**
- `ldv,n` → **می‌رود**
- `hello` → **hello**
- `test@example.com` → **test@example.com**

**چهار سرویس مک.** روی هر متنی که انتخاب کرده باشید، از منوی *Services* می‌توانید آن را
فارسی کنید، با هوش مصنوعی ترجمه کنید، به دیکشنری شخصی اضافه کنید یا به لاتین برگردانید.
(بخش [Services](#services) را ببینید.)

</div>

---

## Features

- **No layout switching.** The English layout stays active the whole time; Persian words are detected and converted.
- **English and technical strings survive.** E‑mail addresses, URLs, file paths, version numbers, code identifiers and numbers are never touched.
- **Zero-width non-joiner.** `می‌رود`, `کتاب‌ها` and `بازی‌ها` are written with the correct ZWNJ.
- **Backspace undoes a conversion.** Press backspace over a converted word to get the Latin text back.
- **Personal dictionary.** Words you always want in Persian, and words you never want converted.
- **Ambiguity resolved by context.** A word that can be read either way follows the sentence around it, or a rule you choose.
- **A menu bar app** for every setting — a small menu for the common things, a full window for the rest.
- **Four macOS Services** that work on any text you select — see [Services](#services).

---

## Requirements

- macOS 14 or later
- Xcode Command Line Tools (`xcode-select --install`)

---

## Install

```bash
git clone <this repository> autotype-mac
cd autotype-mac

bash Scripts/install.sh          # builds and installs both apps
```

The script installs:

| App | Location |
| --- | --- |
| The input method | `~/Library/Input Methods/AutoType.app` |
| The settings app | `~/Applications/AutoType Settings.app` |

### Turn it on

macOS only notices a **new** input method after you log out and back in, so:

1. **Log out and log in again** (or restart the Mac).
2. Open **System Settings → Keyboard → Text Input → Edit…**.
3. Press **+**, choose **AutoType** and add it.
4. Switch to it with **Control + Space** (or the globe key).

The settings app shows whether this has been done yet, and has a button that opens the
right settings pane for you.

> macOS 14 and later scan `~/Library/Input Methods` when the user session starts.
> There is no way around that — it applies to every third‑party input method.

---

## Using it

Type with the English layout. When a word is finished — by a space, a punctuation mark or
a cursor move — AutoType decides what it was:

| Typed | Result | Why |
| --- | --- | --- |
| `sghl` | سلام | Persian dictionary word |
| `;jhfih` | کتاب‌ها | Persian dictionary word, with the ZWNJ |
| `ldv,n` | می‌رود | `می` + `رود` |
| `hello` | hello | English dictionary word |
| `slaam` | سلام | Persian word that is also an English-looking string |
| `fun` | fun | Ambiguous: the surrounding text decides |
| `192.168.1.1` | 192.168.1.1 | Technical string |
| `camelCase` | camelCase | Code identifier |

Two rules keep the guessing honest:

- **Technical strings are never converted.** URLs, e‑mails, paths, versions, code
  identifiers, numbers and clock times are recognised first.
- **A word is only converted when the Persian reading is a real word.** Anything else is
  left exactly as it was typed.

### The English modifier

Hold the right **⌘** (the default) while typing to get plain English without any
conversion. The key can be changed in the settings.

### Direct Persian mode

In this mode every key produces its Persian letter straight away — a plain Persian
layout. Useful when you are writing Persian only.

---

## The settings app

Click the AutoType icon in the menu bar. A small menu shows whether AutoType is running
and carries the two settings you reach for most. **Settings…** opens the full window,
which is divided the way macOS divides its own settings: a sidebar that names the parts
of AutoType, and a pane for the part you are looking at.

| Part of the window | What it holds |
| --- | --- |
| **General** | Whether AutoType is running, the typing mode, ambiguous words, the modifier key that types plain English, Persian numerals and Persian punctuation |
| **Dictionary** | Words that always convert, and words that never do |
| **Translation** | The AI translation that happens when you press Return |
| **Services** | The four AutoType actions, and how to turn them on |
| **About** | The version, the login item and the files AutoType keeps |

Settings live in `~/Library/Application Support/AutoType/settings.json` and
`dictionary.json`. The input method watches that folder, so a change takes effect
immediately — no need to switch applications.

---

## Services

The settings app also publishes four **macOS Services**. They act on whatever text you
have selected in any app that supports Services — no AutoType input method needed.

| Service | What it does |
| --- | --- |
| **AutoType → Convert to Persian** | Turns the selected Latin words into Persian (`sghl ;jhf` → `سلام کتاب`) |
| **AutoType → Translate with AI** | Translates the selection with the configured AI provider |
| **AutoType → Add to Dictionary** | Adds the selected word to your personal dictionary |
| **AutoType → Convert to Latin** | Turns selected Persian back into the Latin keys that produce it (`سلام کتاب` → `sghl ;jhf`) |

### Turning them on

macOS disables third‑party Services until you allow them, once:

1. Open **System Settings → Keyboard → Keyboard Shortcuts → Services**.
2. Tick **AutoType** (and the four entries under it).
3. Optionally give them a shortcut — select the service and press **⌘ + …**.

After that they are in the **Services** submenu of every app that has one:
**Edit → Services**, or right‑click a selection → **Services**.

### Where they appear

Only apps that support the Services menu show them: **TextEdit, Notes, Mail, Safari,
Xcode, Finder** and most native apps. **Chrome, VS Code, Slack and Electron apps do
not** have a Services menu — that is a limitation of those apps, not of AutoType.

### How it works

The four services are declared in the app bundle's `Info.plist` under `NSServices`:

```xml
<key>NSServices</key>
<array>
    <dict>
        <key>NSMenuItem</key>   <dict><key>default</key><string>AutoType/Convert to Persian</string></dict>
        <key>NSMessage</key>    <string>convertSelectionToPersian</string>
        <key>NSPortName</key>   <string>AutoType Settings</string>
        <key>NSSendTypes</key>  <array><string>public.utf8-plain-text</string></array>
    </dict>
    …
</array>
```

macOS then calls the provider — the `ServiceProvider` object in
`Sources/AutoTypeSettings/ServiceProvider.swift` — through a method named after the
message: `convertSelectionToPersian:userData:error:`. The selected text arrives on the
pasteboard, and the answer is written back onto the same pasteboard, where the app that
started the service replaces its selection with it.

> **Note for developers:** macOS only calls these `@objc` methods in an *optimized*
> build. `Scripts/package_app.sh` therefore compiles the debug configuration with
> `-Xswiftc -O` as well; without it AppKit finds the provider, asks whether it
> implements the selector, gets a yes — and then never calls it.

---

## How it works

```
Sources/
  AutoTypeCore/        the engine, with no UI and no macOS input APIs
    PersianLayout      the ISIRI 2901 keyboard map
    Lexicon            the Persian and English word lists
    ConversionEngine   decides what a typed word is
    PersianText        ZWNJ, digits and punctuation helpers
    TechnicalPatterns  strings that must survive untouched
    Settings           the shared configuration
  AutoTypeIME/         the input method itself (InputMethodKit)
    Controller         one instance per application that talks to it
    InputMethod        the server and the connection to the system
  AutoTypeSettings/    the menu bar app (SwiftUI)
  AutoTypeChecks/      a standalone checker that runs without Xcode
```

**The keyboard map** is the ISIRI 2901 layout — the same one macOS itself ships as
*Persian‑ISIRI 2901*, and the one Diyar uses. It was verified against the system layout
rather than copied from a table:

| Key | `q` | `w` | `e` | `r` | `t` | `y` | `u` | `i` | `o` | `p` |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Letter | ض | ص | ث | ق | ف | غ | ع | ه | خ | ح |

| Key | `a` | `s` | `d` | `f` | `g` | `h` | `j` | `k` | `l` | `;` | `'` |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Letter | ش | س | ی | ب | ل | ا | ت | ن | م | ک | گ |

| Key | `z` | `x` | `c` | `v` | `b` | `n` | `m` | `,` |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Letter | ظ | ط | ز | ر | ذ | د | پ | و |

The five punctuation keys `[ ] ; ' ,` carry Persian letters, which is what makes a word
like `o,f` (خوب) recognisable in the first place.

**The dictionaries** hold 395,606 Persian words (Wikipedia and a Persian poetry corpus)
and 238,182 English words. Persian entries keep the spelling from the corpus, including
the zero-width non-joiner, so `میرود` is written `می‌رود`.

**The decision** is a scored one. A token that is technical never reaches the scorer.
Otherwise the Persian reading is looked up in the dictionary; a word that is in both
dictionaries is decided by the surrounding text or by the priority setting; a word in
neither is left alone unless it contains a Persian-only key.

---

## Development

```bash
source Scripts/env.sh

# Build everything
swift build --disable-sandbox --cache-path "$AUTOTYPE_ROOT/.build/cache"

# Run the checks (63 assertions, no Xcode needed)
swift run --disable-sandbox --cache-path "$AUTOTYPE_ROOT/.build/cache" AutoTypeChecks

# Run the swift-testing suite (needs a full Xcode toolchain)
swift test --enable-swift-testing
```

The packaged input method can check itself. It loads the dictionaries and then types a
whole sentence through the real controller, using a stand-in for the text field:

```bash
"$HOME/Library/Input Methods/AutoType.app/Contents/MacOS/AutoTypeIME" --self-test
```

```text
AutoType self test
  persian words:  395606
  english words: 238182
  ✓ sghl → سلام
  ✓ ;jhf → کتاب
  ✓ a typed Persian word is committed
  ✓ a plural keeps its ZWNJ
  ✓ a technical string survives
  ✓ the second backspace undoes the conversion
  ✓ the English modifier types plain English
All self test checks passed.
```

### Scripts

| Script | What it does |
| --- | --- |
| `Scripts/install.sh` | Builds and installs both apps, then registers the input method |
| `Scripts/uninstall.sh` | Removes both apps and the shared configuration |
| `Scripts/package_ime.sh` | Builds `AutoType.app` (`--install` to install it) |
| `Scripts/package_app.sh` | Builds `AutoType Settings.app` (`--install` to install it) |
| `Scripts/build_resources.py` | Rebuilds the dictionaries from the source corpora |
| `Scripts/make_icon.py` | Draws the app and menu bar icons |

---

## Known limitations

- macOS needs one log out / log in after the **first** install, before the input method
  shows up. Later updates are picked up immediately.
- The input method is ad-hoc signed, so Gatekeeper may ask for confirmation the first
  time macOS starts it.
- Only the ISIRI 2901 layout is supported. Other Persian layouts are not.
- The macOS Services only show up in apps that have a **Services** menu (TextEdit,
  Notes, Safari, Xcode, …). Chrome, VS Code and other Electron apps do not have one.

---

## English summary

AutoType is a Persian input method for macOS that never asks you to switch keyboard
layouts. You keep typing on the US layout; words that are Persian are converted
automatically, while English words, technical strings and numbers are left alone. It is
the macOS counterpart of Diyar (Iranux), built on InputMethodKit.

Install it with `bash Scripts/install.sh`, log out and back in once so macOS notices the
new input method, then add **AutoType** under *System Settings → Keyboard → Text Input*.
