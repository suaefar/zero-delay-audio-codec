#!/bin/bash

FILE="$1"

if [ ! -e "${FILE}" ]; then
  echo "file '${FILE}' not found"
  exit 1
fi

SAMPLERATE="44100"

ZDAC_QUALITY=0.0
ZDAC_ENTRY=2.5
ZDAC_RATE=220

OPUS_FRAMESIZE=2.5
OPUS_MAXDELAY=0
OPUS_BITRATE=80

WAVPACK_BITRATE=80
WAVPACK_BLOCKSAMPLES=110

SOURCE_FILE="${FILE%%.wav}_${SAMPLERATE}Hz_24bit.wav"

# Create single channel source file
sox "${FILE}" -c 1 -b 24 -G -r "${SAMPLERATE}" "${SOURCE_FILE}"

# ZDAC
ZDAC_TARGET_FILE="${FILE%%.wav}_${SAMPLERATE}Hz_zdac.wav"
octave -q --eval "
  filename_in = '${SOURCE_FILE}';
  filename_out = '${ZDAC_TARGET_FILE}';
  [bits_per_second, bits_per_sample, num_bits, num_samples, SNR, DEV] = codec(filename_in, filename_out, ${ZDAC_QUALITY}, ${ZDAC_ENTRY}, ${ZDAC_RATE});
  "
ZDAC_SIZE=$(stat --printf="%s" "${ZDAC_TARGET_FILE}.zda")

# OPUS
OPUS_TARGET_FILE="${FILE%%.wav}_${SAMPLERATE}Hz_opus.wav"
opusenc --framesize "${OPUS_FRAMESIZE}" --max-delay "${OPUS_MAXDELAY}" --bitrate "${OPUS_BITRATE}" "${SOURCE_FILE}" "${OPUS_TARGET_FILE}.opus"
opusdec --float "${OPUS_TARGET_FILE}.opus" "${OPUS_TARGET_FILE}"
OPUS_SIZE=$(stat --printf="%s" "${OPUS_TARGET_FILE}.opus")

# WAVPACK-stream
WAVPACK_TARGET_FILE="${FILE%%.wav}_${SAMPLERATE}Hz_wavpack-stream.wav"
wavpack-stream -h -b"${WAVPACK_BITRATE}" --block-samples="${WAVPACK_BLOCKSAMPLES}" "${SOURCE_FILE}" -o "${WAVPACK_TARGET_FILE}.wps"
wvunpack-stream "${WAVPACK_TARGET_FILE}.wps" -o "${WAVPACK_TARGET_FILE}"
WAVPACK_SIZE=$(stat --printf="%s" "${WAVPACK_TARGET_FILE}.wps")

octave  -q --eval "
  graphics_toolkit qt;
  fs = ${SAMPLERATE};
  signals = audioread('${SOURCE_FILE}');
  signals_zda = audioread('${ZDAC_TARGET_FILE}');
  signals_opus = audioread('${OPUS_TARGET_FILE}');
  signals_wavpack = audioread('${WAVPACK_TARGET_FILE}');
  for i=1:size(signals,2)
    signal = signals(:,i);
    signal_zda = signals_zda(:,i);
    signal_opus = signals_opus(:,i);
    signal_wavpack = signals_wavpack(:,i);
    
    zdac_bitrate = 8.*${ZDAC_SIZE}./numel(signal).*fs;
    opus_bitrate = 8.*${OPUS_SIZE}./numel(signal).*fs;
    wavpack_bitrate = 8.*${WAVPACK_SIZE}./numel(signal).*fs;
    
    figure('Position',[0 0 1600 800]);
    subplot(4,3,1);
    plot(signal);
    hold on;
    plot(signal_opus);
    xlabel('samples'); ylabel('amplitude');
    title(sprintf('OPUS @ %.1f kbit/s',opus_bitrate./1000));
    subplot(4,3,4);
    imagesc(log_mel_spectrogram(signal_opus,fs,10,25,[20 16000]),[-100 0]); axis xy; colorbar;
    xlabel('10ms frame-shift'); ylabel('Mel-bands');
    title('OPUS');
    subplot(4,3,7);
    plot(signal_opus-signal);ylim([-0.1 0.1]);
    xlabel('samples'); ylabel('amplitude');
    title('OPUS difference');
    subplot(4,3,10);
    imagesc(log_mel_spectrogram(signal_opus-signal,fs,10,25,[20 16000]),[-100 0]); axis xy; colorbar;
    xlabel('10ms frame-shift'); ylabel('Mel-bands');
    title('OPUS difference');
    
    subplot(4,3,2);
    plot(signal);
    hold on;
    plot(signal_zda);
    xlabel('samples'); ylabel('amplitude');
    title(sprintf('ZDAC @ %.1f kbit/s',zdac_bitrate./1000));
    subplot(4,3,5);
    imagesc(log_mel_spectrogram(signal_zda,fs,10,25,[20 16000]),[-100 0]); axis xy; colorbar;
    xlabel('10ms frame-shift'); ylabel('Mel-bands');
    title('ZDAC');
    subplot(4,3,8);
    plot(signal_zda-signal);ylim([-0.1 0.1]);
    xlabel('samples'); ylabel('amplitude');
    title('ZDAC difference');
    subplot(4,3,11);
    imagesc(log_mel_spectrogram(signal_zda-signal,fs,10,25,[20 16000]),[-100 0]); axis xy; colorbar;
    xlabel('10ms frame-shift'); ylabel('Mel-bands');
    title('ZDAC difference');
    
    subplot(4,3,3);
    plot(signal);
    hold on;
    plot(signal_wavpack);
    xlabel('samples'); ylabel('amplitude');
    title(sprintf('WavPack-stream @ %.1f kbit/s',wavpack_bitrate./1000));
    subplot(4,3,6);
    imagesc(log_mel_spectrogram(signal_wavpack,fs,10,25,[20 16000]),[-100 0]); axis xy; colorbar;
    xlabel('10ms frame-shift'); ylabel('Mel-bands');
    title('WavPack-stream');
    subplot(4,3,9);
    plot(signal_wavpack-signal);ylim([-0.1 0.1]);
    xlabel('samples'); ylabel('amplitude');
    title('WavPack-stream difference');
    subplot(4,3,12);
    imagesc(log_mel_spectrogram(signal_wavpack-signal,fs,10,25,[20 16000]),[-100 0]); axis xy; colorbar;
    xlabel('10ms frame-shift'); ylabel('Mel-bands');
    title('WavPack-stream difference');
    
    set(gcf,'PaperUnits','inches','PaperPosition',[0 0 16 8].*1.4);
    print('-dpng','-r300',sprintf('${SOURCE_FILE%%.wav}-c%i-comparison.png',i));
  end
  "
