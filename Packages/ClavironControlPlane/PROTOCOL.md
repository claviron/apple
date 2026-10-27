# Claviron management protocol

The authoritative protobuf source is the [Claviron management API](https://github.com/claviron/exta/tree/main/crates/grpc/proto).
This package contains generated
Swift messages and client stubs, not another hand-maintained schema.

From the `claviron-apple` repository root, regenerate after a server protocol
change with:

```sh
scripts/generate-protocol.sh generate /path/to/proto
```

Verify that committed bindings still match the authoritative source with:

```sh
scripts/generate-protocol.sh check /path/to/proto
```

The script intentionally excludes `greeter.proto`, which is a server demo and
not part of the Claviron management product surface. `ProtocolSource.lock`
records both the source revision and content hashes. The package pins the code
generator and runtime versions so regeneration is repeatable. Check out the
revision recorded in `ProtocolSource.lock` when reproducing a release; pass
that checkout's `crates/grpc/proto` directory to the script. Check mode compares
the pinned file hashes and generated output, so unrelated later commits in a
source checkout do not invalidate an unchanged protocol.

Application builds use the committed Swift bindings. Regeneration is a
maintainer operation and does not require a sibling repository layout.
