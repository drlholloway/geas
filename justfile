# Geas task runner (https://github.com/casey/just). `just --list`.

set shell := ["bash", "-cu"]
export PATH := "/opt/homebrew/bin:" + env_var("PATH")

# fetch dependencies for the whole workspace
get:
    dart pub get

# static analysis everywhere
analyze:
    dart analyze

# run every test suite
test:
    cd packages/geas_core && dart test
    cd apps/geas_cli && dart test

format:
    dart format .

# compile the CLI to build/geas
cli:
    mkdir -p build
    dart compile exe apps/geas_cli/bin/geas.dart -o build/geas
