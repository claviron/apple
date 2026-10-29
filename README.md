# Claviron for Apple

Native GUI for managing Claviron servers over gRPC on Apple platforms.

The app runs on macOS, iPhone and iPad.

Connect to your servers over TLS/mTLS, keep several saved connections, and
manage their runtime and hosting services from one app.

- Inspect workers, services, applications and tasks, and run the management
  actions your server exposes.
- Browse sites and manage DNS, domains and certificates.
- Manage users, roles and permissions through the server's management schema.
- Create client certificates with a selected user and certificate permissions
  when the server provides those operations.

The server reports its capabilities and validates changes. Editable user fields
and their form layout come from its schema, so the app can manage different
applications without embedding their database models.

## Download for macOS

Download the Universal preview from [GitHub Releases](https://github.com/claviron/apple/releases).
It supports Apple Silicon and Intel Macs running macOS 26 or later. Extract the
ZIP and move `Claviron.app` to `/Applications`.

## Connect to a server

Enable the Claviron management API on your server and obtain its CA certificate,
a client certificate and the matching private key. On first launch, enter a
connection name and management endpoint, such as
`https://management.example.com:9443`, then import those PEM files.

Saved servers reference reusable TLS profiles. Configuration is stored in the
app's Application Support directory as `Claviron/configuration.plist`. Imported
credentials stay in the app's private credential directory with restricted file
permissions; iOS also applies complete file protection. These are local app
data, separate from this source repository.

## Build from source

Requirements: Xcode 26 or newer with Swift 6.2 support. The app targets macOS 26
and iOS/iPadOS 26 or newer.

Open `claviron-apple.xcodeproj`, select the `Claviron` scheme and choose your
destination. Swift Package Manager resolves the dependencies. Generated gRPC
bindings are included, so an ordinary build needs only this repository.

For a macOS build without signing:

```sh
xcodebuild -project claviron-apple.xcodeproj -scheme Claviron \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

For signing, copy `Configurations/Signing.example.xcconfig` to
`Configurations/Signing.local.xcconfig` and set your Apple Developer team.
The local file is ignored by Git. Use an appropriate bundle identifier for
your team when building for a physical device or distribution.

`scripts/install-macos.sh` builds a local Release app and installs it into
`/Applications`. Its signing settings come from the project and your local
configuration.

## Protocol and development

The shared [ClavironControlPlane](Packages/ClavironControlPlane) package owns
the direct gRPC transport, management observations and protocol bindings.
[Protocol regeneration](Packages/ClavironControlPlane/PROTOCOL.md) is pinned by
source revision, file hashes and generator versions.

The app tests are in `ClavironTests`; shared-core tests are in the Swift
package. Run the app tests from Xcode, or the shared-core tests with:

```sh
swift test --package-path Packages/ClavironControlPlane
```

See [application icon codes](docs/ApplicationIcons.md) for supported runtime
and framework identifiers.

## License

Licensed under [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE), at your option.
Brand assets and dependencies retain their own terms; see
[third-party notices](THIRD_PARTY_NOTICES.md).
