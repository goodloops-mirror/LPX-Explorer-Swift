#!/bin/bash
# Regenerate Tests/Golden/*.json from the legacy Rust parser (the oracle) over
# example_projects/. Read-only on the projects. Golden files are git-ignored
# because they contain real project/track/plug-in names.
set -euo pipefail
cd "$(dirname "$0")/.."
cargo build --release --manifest-path scripts/oracle/Cargo.toml
scripts/oracle/target/release/oracle example_projects Tests/Golden
ls Tests/Golden | wc -l
