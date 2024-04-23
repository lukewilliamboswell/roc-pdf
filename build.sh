cargo build

cp platform/target/debug/libroc_pdf_experiment.a platform/macos-arm64.a

# UNCOMMENT to bundle into URL package for distribution
# roc build --bundle .tar.br platform/main.roc
