#!/bin/zsh
# Coverage check (listening transcripts + reading text) for every book that has assembled exams.
# Output: ~/ielts-data/qa/BOOK.txt
mkdir -p ~/ielts-data/qa
for b in "$@"; do
  { echo "### $b listening"; ~/ielts-tools/qa/coverage.py $b auto listening 2>&1
    echo "### $b reading";   ~/ielts-tools/qa/coverage.py $b auto reading 2>&1; } > ~/ielts-data/qa/$b.txt
done
