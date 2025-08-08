#!/usr/bin/env bash
set -e
PROTO_DIR=protocol
SWIFT_OUT=macos
KOTLIN_OUT=android/app/src/main/java

protoc -I="$PROTO_DIR" \
       --swift_out="$SWIFT_OUT" \
       --plugin=protoc-gen-swift="$(which protoc-gen-swift)" \
       --kotlin_out="$KOTLIN_OUT" \
       "$PROTO_DIR"/*.proto

echo "✅ Código Protobuf gerado para Swift e Kotlin"