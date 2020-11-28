#!/bin/bash
mkdir "target_zda"
ls -1 32k_32bit_2c_ZDA-P3-Q0-E1/ | while read line; do sox "32k_32bit_2c_ZDA-P3-Q0-E1/$line" --norm -b 16 -r 44100 "target_zda/$line"; done

mkdir "target_orig"
ls -1 source/ | while read line; do sox "source/$line" --norm -b 16 -r 44100 "target_orig/$line"; done
