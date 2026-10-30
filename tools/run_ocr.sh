#!/bin/zsh
# OCR all books, 4 in parallel
cd ~/ielts-refs/zeeklog/repo
books=(4 5 6 7 8 9 10 11 12 13 14 15 16 17 18)
for b in $books; do
  echo "~/ielts-tools/pdfocr '剑桥雅思真题$b.pdf' ~/ielts-data/ocr/C$b 1400 all > ~/ielts-data/ocr/C$b.log 2>&1"
done | xargs -P 4 -I{} zsh -c "{}"
echo ALLDONE
