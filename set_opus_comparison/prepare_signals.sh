#!/bin/bash
mkdir "32k_32bit_2c"
ls -1 source/ | while read line; do sox "source/$line" -b 32 -G -r 32000 "32k_32bit_2c/$line"; done

mkdir "44k_32bit_2c"
ls -1 source/ | while read line; do sox "source/$line" -b 32 -G -r 44100 "44k_32bit_2c/$line"; done

