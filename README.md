![Image](images/bitmap.png)
# A free zero-delay audio codec (zdac)
Compress and encode audio data with no reference to future samples, using:
1) (linear) predictive coding,
2) adaptive quantization of the residue steered by a masking model,
3) and entropy coding (Huffman)

Author: [Marc René Schädler](mailto:suaefar@googlemail.com)

## Status
Currently in conception phase:
- Working implementation in GNU/Octave
- Tuning default parameters
- Adding documentation


## Somewhat more detailed description
will follow soon


## Usage
First, run `./setup.sh` to generate some needed files (needs octave, octave-signal and liboctave-dev).
This generates the codebooks and compiles a mex file used to set up the Gammatone filter bank.

Then, run `play_demo.m` (in Octave) to see if encoding and decoding works.
This script encodes and decodes a signal and shows the state of some internal variables of the encoder.

Run `./run_benchmark.sh <folder-with-wav-files-sampled-at-32kHz> <PREDICTOR> <QUALITY> <ENTRY>` to encode and decode the audio files in the folder and get some encoding statistics where considered default values are as follows: PREDICTOR = 3, QUALITY = 0, ENTRY = 10.


### PREDICTOR
The predictor predicts the next sample values based on past sample values.
It is deterministic and runs in the encoder and in the decoder.
The variance in the signal that can be predicted from the past samples doesn't have to be transmitted.
If the predictor works well, the residual signal has only low amplitude and can be encoded with fewer bits.
The improvements to the bit rate by the predictor are lossless.

Available predictors are:

0) [Zero](predictor_zero.m) predicts always zero
1) [Simple](predictor_simple.m) predicts the last value
2) [Linear extrapolation](predictor_linear.m) Extrapolates linearly using the last 2 samples
3) [Linear predictive coding](predictor_lpc.m) Uses LPC with (max) three coefficients on the (max) last 32 samples to predict the next sample analysis filter width, and inserts and entry-point every 10ms.


### QUALITY
The encoder estimates the current masking with a 39-band Gammatone filterbank.
The Q-factor (i.e., width) of these filters is steered with the quality variable.
The improvements to the bit rate by the masking model come with a loss of information.
In the ideal case, the loss is not perceivable.

Negative values mean broader filters, and hence increase the spectral masking of off-frequency signal parts.
A value of 0 is the default width, while -2 doubles the filter width, and -4 results in a quarter of the default filter width.
Values greater than one make the the filters narrower and result in decreased spectral masking, that is, less loss of information.
However, values greater than 1 probably don't make much sense.


### ENTRY
The encoder inserts from time to time the information that is required to start decoding the bit-stream.
The default is every 10 ms, which corresponds to every 320 samples at 32kHz sampling rate.
This includes encoding the current sample value with 20 bit precision and resets the predictor, because values prior to the entry point might be unknown to the decoder.
Adding entry points more often will increase the required bits to encode the stream.
This variable does not add a delay to the encoded bit-stream, but low values, e.g. 1ms, ensure that the decoder can recover quickly if data was lost during the transmission.


## Performance (in terms of achievable bit rates)
A small parameter space exploration for different values for QUALITY and ENTRY.
Read the corresponding [README.md](set_opus_comparison/README.md) on how to achieve the required audio samples.
Once prepared, the following commands encode and decode the channels of these files with different parameters and generate basic statistics on their bit rates.

    for QUALITY in 0 -2 -4; do
      for ENTRY in 1 2 4 8; do
        ./run_benchmark.sh set_opus_comparison/32k_32bit_2c/ 3 $QUALITY $ENTRY
      done
    done | tee results.txt

    for QUALITY in 0 -2 -4; do
      for ENTRY in 1 2 4 8; do
        RATES="[$(cat results.txt  | grep "\-Q${QUALITY}-E${ENTRY}/" | cut -d' ' -f7 | tr -s "\n" | tr "\n" ",")]";octave -q --eval "rates=${RATES};printf('QUALITY=%.1f ENTRY=%.1f %.0f %.0f %.0f kbit/s\n',${QUALITY},${ENTRY},mean(rates)./1000,min(rates)./1000,max(rates)./1000)"
      done
    done

Encoding each sample with 16 bit, the required bit rate would be (16*32000 =) 512 kbit/s.
The achieved average/minimum/maximum bit rates in kbit/s (per channel) across files are as follows:

| QUALITY | ENTRY | AVG | MIN | MAX |
|--------:|------:|----:|----:|----:|
|       0 |     1 | 249 | 184 | 323 |
|       0 |     2 | 222 | 161 | 290 |
|       0 |     4 | 205 | 148 | 267 |
|       0 |     8 | 196 | 141 | 253 |
|      -2 |     1 | 230 | 176 | 285 |
|      -2 |     2 | 203 | 153 | 251 |
|      -2 |     4 | 186 | 140 | 231 |
|      -2 |     8 | 176 | 132 | 221 |
|      -4 |     1 | 189 | 163 | 214 |
|      -4 |     2 | 162 | 140 | 192 |
|      -4 |     4 | 145 | 127 | 178 |
|      -4 |     8 | 136 | 119 | 170 |

More detailed statistics can be found the [reference results](results_reference.txt).
An example of how to read the data:

    RESULT: set_opus_comparison/32k_32bit_2c_ZDA-P3-Q0-E1/./03-12-German-male-speech.441.wav 1 3 0.0 1.0 252621.6 7.894 250884 1980585/1619821/180343/85400/95018 -39.0 -32.8

Of the file 03-12-German-male-speech.441.wav the channel 1 was compressed with predictor 3, quality 0.0, and entry 1.0 with an average of 252621.6 bit/s, i.e. 7.894 bit per sample.
The encoder compressed 250884 samples to 1980585 bits, of which 1619821 were used to encode significant values, 180343 to encode exponent values, 85400 to encode entry points, and 95018 to encode codebook updates.
The signal-to-(quantization)noise ratio is -39 dB, the largest deviation in a single sample value was -32.8 dB.

If you run the benchmark script, you can find the decoded samples in corresponding set_opus_comparison/32k_32bit_2c_ZDA-* folders and judge the quality for yourself.


## Preliminary conclusion
The approach could approximately half the required bandwidth for ultra-low-latency audio applications.

The saved bandwidth could be used for redundancy, i.e. sending each packet twice.

