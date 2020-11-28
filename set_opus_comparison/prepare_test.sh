#!/bin/bash

mkdir test;

ls -1 target_orig/ | while read line; do
  case $(($RANDOM % 2)) in
    0)
      cp "target_orig/$line" "test/${line%%.wav}_X.wav"
      cp "target_zda/$line" "test/${line%%.wav}_O.wav"
      echo "$line X"
    ;;
    1)
      cp "target_orig/$line" "test/${line%%.wav}_O.wav"
      cp "target_zda/$line" "test/${line%%.wav}_X.wav"
      echo "$line O"
    ;;
  esac
done
