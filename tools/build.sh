#!/bin/zsh
# Compiles the Swift helpers used by the extraction pipeline (macOS, Xcode command-line tools).
set -e
cd "$(dirname "$0")"
for f in pdfocr pdfrender pdftext pdfinfo pdfboxes pdfheads ocrtest montage gifframes; do swiftc -O $f.swift -o $f; done
swiftc -O figcrop.swift -o bin/figcrop-bin
swiftc -O ocrregion.swift -o bin/ocrregion-bin
swiftc -O qa/dewatermark.swift -o qa/dewatermark
echo built
