<p align="center">
  Language: <a href="README.md">Русский</a> · <strong>English</strong>
</p>

# Rusifikator

[![Latest release](https://img.shields.io/github/v/release/xonika9/rusifikator-macos?label=release)](https://github.com/xonika9/rusifikator-macos/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/xonika9/rusifikator-macos/total?label=downloads)](https://github.com/xonika9/rusifikator-macos/releases)
[![macOS 26+](https://img.shields.io/badge/macOS-26%2B-black?logo=apple&logoColor=white)](#installation)
[![MIT license](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

A menu bar utility that turns a raw voice transcript into clean Russian prose. Dictate, paste the transcript, get readable text without the false starts, repetitions and misheard words.

- Lives in the menu bar, opens with a single click, and stays out of the Dock.
- Every run is isolated: a request carries only the fixed system prompt and the text currently in the field.
- The last five results are stored locally and never travel with a new request.
- Works with any OpenAI-compatible provider over HTTPS; the key lives in the Keychain.

> I publish field notes on AI models and developer tooling in [Контролируемые галлюцинации](https://t.me/+DOZWlhI4r4EyYjgy), a Russian-language Telegram channel.

## Installation

Requires macOS 26 or newer on Apple Silicon.

1. Download `Rusifikator-<version>.dmg` from the [latest release](https://github.com/xonika9/rusifikator-macos/releases/latest).
2. Open the disk image and drag Rusifikator into Applications.
3. Launch it. macOS will refuse the first launch — that is expected, see below.

The application carries a local ad-hoc signature and no Apple Developer ID certificate, so the first launch is unblocked by hand, once:

1. try to open the application from Applications;
2. open System Settings → Privacy & Security;
3. under Security, click "Open Anyway" and confirm with your password.

After that it opens on a double click like anything else. The limits of this arrangement are described under [Signing and Gatekeeper](#signing-and-gatekeeper).

## Usage

The icon appears in the menu bar. A left click opens the editor, a right click opens a menu with the version, settings and quit.

Before the first run, open the settings, enter your API key and press Save. The defaults are the endpoint `https://liteapi.gotacat.dev/`, the model `proxy/gpt-5.6-terra` and the route `POST /v1/chat/completions`; all of them can be pointed at any other OpenAI-compatible provider.

From there the loop is simple: paste the transcript, run the cleanup, copy the result. The connection test next to the settings sends a short service string and reports whether the provider answers, without saving the draft values from the window.

Two habits worth knowing in advance:

- **One instance per session.** A second launch brings the running copy forward and exits immediately — no second menu bar icon appears.
- **The editor tidies up after itself.** If the window stayed closed for a minute or longer, the next opening starts with an empty field. History is left alone, and a request that is still running is never interrupted: it finishes and lands in history.

## Updates

Settings carry a "Проверить обновления" action, with the current state next to it: checking, up to date, a new version is available, or the check failed. Once a day the application consults the channel quietly and never interrupts your work — the update window only opens on an explicit click.

Updates run on [Sparkle](https://sparkle-project.org), the standard update mechanism for macOS applications distributed outside the App Store:

- metadata and the disk image are fetched over HTTPS only;
- the image is verified by an EdDSA signature before it is unpacked, and a modified file is not installed;
- the owner confirms the installation, after which the application relaunches;
- quarantine is cleared from a verified update, so the unblocking step from Installation is not repeated.

Updating is refused while the application runs from a mounted disk image or a quarantined copy: move it to Applications first. The application says so explicitly in that case.

## Privacy

- The provider endpoint and the model live in `UserDefaults`; the API key lives only in the Keychain, bound to the provider's HTTPS origin. Changing providers requires entering the key again.
- A request carries the system prompt and the current field text. Local history is never appended to a request.
- The last five source/result pairs are kept in a JSON file inside Application Support. History can be erased from the application; it never reaches analytics or logs.
- The update check talks only to the update channel and sends no text, no settings and no API key.
- Copying happens only on an explicit click. After that the text sits in the system pasteboard, reachable by clipboard managers, Universal Clipboard and other applications.
- The provider receives the current transcript. Its retention and processing rules are outside this application's control and have to be judged separately.

## Signing and Gatekeeper

The project has no Apple Developer ID certificate and no notarization. What follows from that:

| | Current state |
| --- | --- |
| First launch | Gatekeeper blocks the ad-hoc signature; unblocked by hand, once |
| Updates | Verified by EdDSA; quarantine is cleared, so no repeat unblocking |
| What replaces Developer ID | The application trusts only images signed with the owner's private key |
| macOS protections | Nothing is disabled: Gatekeeper, quarantine and signature checks work normally |
| Architecture | Built for Apple Silicon and marked `arm64`; Intel Macs will not receive updates |
| Signing key | Without Developer ID, `SUPublicEDKey` cannot be rotated through an update |

Obtaining a certificate later breaks nothing for installed copies; what changes then is described in [docs/RELEASING.md](docs/RELEASING.md).

## Building from source

The project deliberately stays a compact Swift Package.

```sh
swift build
swift test
scripts/package-app.sh
scripts/smoke-test-app.sh dist/Rusifikator.app
```

The bundle lands in `dist/Rusifikator.app`. Environment details, working in Xcode and the rules for changes are in [CONTRIBUTING.md](CONTRIBUTING.md); the release process is in [docs/RELEASING.md](docs/RELEASING.md).

## Contributing and security

Bug reports, reproducible compatibility findings and focused improvements are welcome — start with [CONTRIBUTING.md](CONTRIBUTING.md). Report vulnerabilities through [SECURITY.md](SECURITY.md) rather than a public issue. Conduct is covered by the [Code of Conduct](CODE_OF_CONDUCT.md).

Version history lives in [CHANGELOG.md](CHANGELOG.md).

## License

[MIT](LICENSE).
