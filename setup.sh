#!/bin/bash

mkoctfile --mex iir4.c
octave --eval "zdaenc(1,32000);"
