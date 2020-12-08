#!/bin/bash
# This file is part of the ZDAC reference implementation
# Author (2020) Marc René Schädler (suaefar@googlemail.com)

FOLDER="$1"
QUALITY="$2"
ENTRY="$3"
NPROC="$4"

[ -z "$NPROC" ] && NPROC=$(nproc)

FILELIST="$(mktemp)"

(cd "${FOLDER}" && find . -iname '*.wav' -type f) | sort -R > "${FILELIST}"

for ((I=0;$I<${NPROC};I++)); do
  octave --eval "
    n = ${NPROC};
    files = importdata('${FILELIST}');
    n = min(length(files),n);
    indir = '${FOLDER%%/}';
    outdir = '${FOLDER%%/}_ZDA-Q${QUALITY}-E${ENTRY}';
    mkdir(outdir);
    for i=1+${I}:n:length(files)
      filename_in = [indir filesep files{i}]
      filename_out = [outdir filesep files{i}];
      codec(filename_in, filename_out, ${QUALITY}, ${ENTRY})
    end" &
done 2>/dev/null | grep RESULT
wait
rm "${FILELIST}"

