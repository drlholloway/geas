# Geas task runner (https://github.com/casey/just). `just --list`.

set shell := ["bash", "-cu"]
export PATH := "/opt/homebrew/bin:" + env_var("PATH")

app := "apps/geas"

# fetch dependencies for the whole workspace
get:
    flutter pub get

# static analysis everywhere
analyze:
    dart analyze
    cd {{app}} && flutter analyze

# run every test suite
test:
    cd packages/geas_core && dart test
    cd apps/geas_cli && dart test
    cd {{app}} && flutter test

format:
    dart format .

# redraw the icon masters and regenerate the platform icon sets
icons:
    python3 packaging/icon/make_icon.py
    cd {{app}} && dart run flutter_launcher_icons

# compile the CLI to build/geas
cli:
    mkdir -p build
    dart compile exe apps/geas_cli/bin/geas.dart -o build/geas

run-macos:
    cd {{app}} && flutter run -d macos

run-android:
    cd {{app}} && flutter run -d android

run-linux:
    cd {{app}} && flutter run -d linux
