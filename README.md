![Image](images/bitmap.png)
# A free zero-delay audio codec (zdac)
Compress and encode audio data with no reference to future samples, using:
1) (linear) predictive coding,
2) adaptive quantization of the residue steered by a masking model,
3) and entropy coding (Huffman)

Author: [Marc René Schädler](mailto:suaefar@googlemail.com)


## Status
Currently in conception phase:
- Working implementation in GNU/Octave (done)
- Tuning default parameters (almost done)
- Adding documentation (ongoing)
- Implementation in C (not started)


## Somewhat more detailed description
will follow soon


## Usage
First, run `./setup.sh` to generate some needed files (needs octave, octave-signal and liboctave-dev).
This generates the codebooks and compiles a mex file used to set up the Gammatone filter bank.

Then, run `play_demo.m` (in Octave) to see if encoding and decoding works.
This script encodes and decodes a signal and shows the state of some internal variables of the encoder.

Run `./run_benchmark.sh <folder-with-wav-files-sampled-at-32kHz> <PREDICTOR> <QUALITY> <ENTRY>` to encode and decode the audio files in the folder and get some encoding statistics where the currently considered default values are as follows: PREDICTOR = 3, QUALITY = 0, ENTRY = 10.

To compare ZDAC to OPUS at compareable bit rates you can run `./run_opus_comparison.sh <WAVFILE> <OPUS_BITRATE> <ZDA_PREDICTOR> <ZDA_QUALITY> <ZDA_ENTRY>`.
The script encodes and decodes the WAVFILE and produces a figure comparing the respective differences to the input signal in the time domain and in the log Mel-spectrogram domain.
After the first run with OPUS_BITRATE=512, add the bitrates of the (possibly two) channels encoded with ZDAC and set OPUS_BITRATE to this value.
The figures are saved in png-files for each channel separately.
The comparison is not ideal, because ZDAC is developed with a target samplerate of 32kHz and OPUS is not compatible with this setting, which requires resampling prior to the comparison.

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
3) [Linear predictive coding](predictor_lpc.m) Uses LPC with (max) three coefficients on the (max) last 32 samples to predict the next sample

Possible future predictors could be:
4) [Deep neural network predictor] Not implemented but possibly better than LPC?

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
The theoretical limit with the chosen approach is 1 bit per sample, and would result in (1*32000 =) 32 kbit/s.
However, that would require to constrain the Huffman tree generation, which is not implemented.
Hence, an additional prefix bit currently indicates if a significant value or a controlcode was transmitted, resulting in a minimum of 2 bit per sample, i.e. (2*32000 =) 64 kbit/s.

The following average/minimum/maximum bit rates in kbit/s (per channel) across files were achieved:

| QUALITY | ENTRY | AVG | MIN | MAX |
|--------:|------:|----:|----:|----:|
|       0 |     1 | 249 | 184 | 323 |
|       0 |     2 | 222 | 161 | 290 |
|       0 |     4 | 205 | 148 | 267 |
|       0 |     8 | 196 | 141 | 253 |
|       0 |    16 | 191 | 137 | 245 |

| QUALITY | ENTRY | AVG | MIN | MAX |
|--------:|------:|----:|----:|----:|
|      -2 |     1 | 230 | 176 | 285 |
|      -2 |     2 | 203 | 153 | 251 |
|      -2 |     4 | 186 | 140 | 231 |
|      -2 |     8 | 176 | 132 | 221 |
|      -2 |    16 | 171 | 129 | 216 |

| QUALITY | ENTRY | AVG | MIN | MAX |
|--------:|------:|----:|----:|----:|
|      -4 |     1 | 189 | 163 | 214 |
|      -4 |     2 | 162 | 140 | 192 |
|      -4 |     4 | 145 | 127 | 178 |
|      -4 |     8 | 136 | 119 | 170 |
|      -4 |    16 | 131 | 115 | 167 |

| QUALITY | ENTRY | AVG | MIN | MAX |
|--------:|------:|----:|----:|----:|
|      -6 |     1 | 147 | 140 | 176 |
|      -6 |     2 | 124 | 115 | 152 |
|      -6 |     4 | 111 |  99 | 138 |
|      -6 |     8 | 105 |  91 | 131 |
|      -6 |    16 | 101 |  87 | 127 |

More detailed statistics can be found the [reference results](results_reference.txt).
An example of how to read the data:

    RESULT: set_opus_comparison/32k_32bit_2c_ZDA-P3-Q0-E1/./03-12-German-male-speech.441.wav 1 3 0.0 1.0 252621.6 7.894 250884 1980585/1619821/180343/85400/95018 -39.0 -32.8

Of the file 03-12-German-male-speech.441.wav the channel 1 was compressed with predictor 3, quality 0.0, and entry 1.0 with an average of 252621.6 bit/s, i.e. 7.894 bit per sample.
The encoder compressed 250884 samples to 1980585 bits, of which 1619821 were used to encode significant values, 180343 to encode exponent values, 85400 to encode entry points, and 95018 to encode codebook updates.
The signal-to-(quantization)noise ratio is -39 dB, the largest deviation in a single sample value was -32.8 dB full-scale.

If you run the benchmark script, you can find the decoded samples in corresponding set_opus_comparison/32k_32bit_2c_ZDA-* folders and judge the quality for yourself.


## Quick preliminary conclusion
The approach could approximately half the required bandwidth for ultra-low-latency audio applications.
Short term (<1ms) variability in the bit rate is probably considerable (up to approx 350 kbit/s).


## Discussion on possible applications
Some discussion on the #xiph channel on freenode.org brought up objections against developing a codec which falls between raw PCM (zero-delay) and OPUS (min 2.5ms delay).
The main objections were:

1) Large network overhead renders the effort useless: IP4/UDP at least needs 224 bit per packet, IP6 is worse
2) The latency due to other network components is much larger: That is, we are optimizing on the wrong front

That triggered some thoughts about possible applications, where these two arguments do not apply.

The main advantage of ZDAC, in a prospective real-time implementation, should be that there is no limitation on block sizes, just like with PCM.
While using less bits to encode the sampled values, the quality should be perceptually on-par with 16 bit PCM.

That makes it's use attactive in cases where bandwidth matters, but close-to-no-latency combined with close-to-no-compromise-in-quality are the top priorities.
This puts some applications to the top of the list (only considerung latency, bandwidth, and quality; in exactly that order):

1) Natural acoustic interaction over distance: Achieve be-in-the-same-room perception (desireable for any acoustic interaction between humans)
2) Where airtime is more costly than cpu-cylces but zero-delay is a hard constraint (streaming between hearing devices?)
3) Where the saved bits can be used for other synced real-time ultra-low-delay data (positional data?)
4) Where the number of audiochannels would make using raw PCM infeasible in a context of zero-delay applications (e.g. with higher-order ambisoncis? wavefield synthesis?)

It remains to be investigated in which applications a reasonable benefit can be found.

My bet is on fiber-connected devices with low-latency (non-USB) sound equipment for the natural acoustic interaction of several humans on both sides.
Several audio streams would enable custom client-side downmixing with rich spatial information (e.g., with https://github.com/gisogrimm/ovbox).
Or, with several microphones and several loudspeakers, even remote spatial perception could be enabled.
Fiber-links can have, at least in the same city, latencies below 1ms.
Non-USB sound cards can achive latencies below 3 ms.
Counting another 1ms jitter buffer and 0.5 ms packet size it seems possibly to stay in the range of 10 ms acoustic round trip time.

The delay added by any codec would add twice to that number (minus 0.5 ms).

Also, the saved bandwidth could be used for redundancy, i.e. sending each packet twice, to avoid drop-outs, which is another important factor for sound quality.






