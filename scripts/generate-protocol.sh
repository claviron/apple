#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
package_dir="$repository_dir/Packages/ClavironControlPlane"
mode=${1:-check}
proto_dir=${2:-}
lock_file="$package_dir/ProtocolSource.lock"

usage() {
    echo "usage: $0 [generate|check] <authoritative-proto-directory>"
}

if [ "$mode" = "--help" ] || [ "$mode" = "-h" ]; then
    usage
    exit 0
fi

case "$mode" in
    generate|check) ;;
    *)
        usage >&2
        exit 2
        ;;
esac

if [ "$#" -ne 2 ] || [ -z "$proto_dir" ]; then
    usage >&2
    exit 2
fi

proto_dir=$(CDPATH= cd -- "$proto_dir" && pwd)
lock_value() {
    awk -F= -v key="$1" '$1 == key { sub(/^[^=]*=/, ""); print; count++ } END { if (count != 1) exit 1 }' "$lock_file"
}

source_repository=$(lock_value source_repository)
if [ "$mode" = "check" ]; then
    # Verification checks the pinned bytes, independently of later repository commits.
    source_revision=$(lock_value source_revision)
    source_relative_dir=$(lock_value source_directory)
else
    source_root=$(git -C "$proto_dir" rev-parse --show-toplevel)
    source_revision=$(git -C "$source_root" rev-parse HEAD)
    case "$proto_dir" in
        "$source_root") source_relative_dir=. ;;
        "$source_root"/*) source_relative_dir=${proto_dir#"$source_root"/} ;;
        *) echo "protocol directory must be inside its source repository" >&2; exit 1 ;;
    esac
    if [ -n "$(git -C "$source_root" status --porcelain -- "$source_relative_dir")" ]; then
        echo "commit authoritative protocol changes before generating bindings" >&2
        exit 1
    fi
fi

protocol_files="
acme.proto
aliases.proto
certificates.proto
applications.proto
dns.proto
domains.proto
linked.proto
management.proto
mtls.proto
server.proto
services.proto
tasks.proto
users.proto
workers.proto
"

work_dir=$(mktemp -d "$package_dir/.protocol-generation.XXXXXX")
trap 'rm -rf -- "$work_dir"' EXIT HUP INT TERM
staged_proto_dir="$work_dir/Protos"
staged_generated_dir="$work_dir/Generated"
staged_lock="$work_dir/ProtocolSource.lock"
mkdir -p "$staged_proto_dir" "$staged_generated_dir"

for protocol_file in $protocol_files; do
    if [ ! -f "$proto_dir/$protocol_file" ]; then
        echo "missing authoritative protocol: $proto_dir/$protocol_file" >&2
        exit 1
    fi
    cp "$proto_dir/$protocol_file" "$staged_proto_dir/$protocol_file"
done

swift package \
    --package-path "$package_dir" \
    --allow-writing-to-package-directory \
    generate-grpc-code-from-protos \
    --no-servers \
    --access-level internal \
    --file-naming dropPath \
    --output-path "$staged_generated_dir" \
    -- "$staged_proto_dir"

{
    echo "source_repository=$source_repository"
    echo "source_revision=$source_revision"
    echo "source_directory=$source_relative_dir"
    echo "generator_grpc_swift_protobuf=2.4.1"
    echo "runtime_grpc_swift=2.4.3"
    echo "runtime_grpc_swift_nio_transport=2.9.2"
    echo "runtime_swift_protobuf=1.38.1"
    for protocol_file in $protocol_files; do
        shasum -a 256 "$proto_dir/$protocol_file" | awk -v name="$protocol_file" '{print "sha256_" name "=" $1}'
    done
} > "$staged_lock"

generated_dir="$package_dir/Sources/ClavironControlPlane/Generated"

if [ "$mode" = "check" ]; then
    diff -ru "$generated_dir" "$staged_generated_dir"
    diff -u "$lock_file" "$staged_lock"
    echo "Generated Swift protocol bindings match the authoritative source."
    exit 0
fi

rm -rf -- "$generated_dir"
mkdir -p "$generated_dir"
cp "$staged_generated_dir"/*.swift "$generated_dir/"
cp "$staged_lock" "$lock_file"
echo "Generated Swift protocol bindings from $source_relative_dir at $source_revision."
