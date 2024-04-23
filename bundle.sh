cargo build --release

cp target/release/libhost.a platform/macos-arm64.a

roc build --bundle .tar.br platform/main.roc