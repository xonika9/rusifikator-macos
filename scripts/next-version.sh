#!/bin/zsh

# Prints the calendar version of the next release: YY.M.D.N, where the date is
# today's in Moscow and N continues that day's sequence of release tags.
# Reads local tags only, so fetch the public ones first.

set -euo pipefail

repo_root=${0:A:h:h}

today=$(TZ=Europe/Moscow date '+%y.%-m.%-d')
tags=$(git -C "$repo_root" tag --list "v$today.*")
last=0
for tag in ${(f)tags}; do
  number=${tag#"v$today."}
  [[ "$number" == [1-9]<-> || "$number" == [1-9] ]] || continue
  (( number > last )) && last=$number
done

print "$today.$(( last + 1 ))"
