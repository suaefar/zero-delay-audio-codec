# A free zero-delay audio codec (zdac)

Author: [Marc René Schädler](mailto:suaefar@googlemail.com)

## Idea
Compress and encode audio data with no reference to future samples,
using (linear) predictive coding, entropy coding (Huffman), and adaptive
quantization steered by a masking model.

## Conception phase
- Working implementation in GNU/Octave
- Description will follow

## Usage
First, run setup.sh to generate some needed files (needs octave, octave-signal and liboctave-dev)

Then, run play_demo.m (in Octave) to see if encoding and decoding works.

Run ./run_benchmark.sh <folder with wav files sampled at 32kHz> <PREDICTOR> <QUALITY> <ENTRY> to encode and decode the audio files in the folder and get some encoding statistics

Defaults:
 
PREDICTOR = 3

QUALITY = 0

ENTRY = 10


