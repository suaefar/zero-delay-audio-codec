#!/bin/bash

FILE="$1"
OPUSRATE="$2"
PREDICTOR="$3"
QUALITY="$4"
ENTRY="$5"

if [ ! -e "${FILE}" ]; then
  echo "file '${FILE}' not found"
  exit 1
fi
soxi "${FILE}"

opusenc --framesize 2.5 --max-delay 0 --bitrate "${OPUSRATE}" "${FILE}" "${FILE%%.wav}_${OPUSRATE}.opus"
opusdec --float "${FILE%%.wav}_${OPUSRATE}.opus" "${FILE%%.wav}_opus${OPUSRATE}.wav"
sox "${FILE%%.wav}_opus${OPUSRATE}.wav" -b 32 -G -r 32000 "${FILE%%.wav}_opus${OPUSRATE}_32k_32bit.wav"
soxi "${FILE%%.wav}_opus${OPUSRATE}_32k_32bit.wav"

sox "${FILE}" -b 32 -G -r 32000 "${FILE%%.wav}_32k_32bit.wav"
soxi "${FILE%%.wav}_32k_32bit.wav"
octave -q --eval "
  filename_in = '${FILE%%.wav}_32k_32bit.wav';
  filename_out = '${FILE%%.wav}_32k_32bit_ZDA_Q${QUALITY}-E${ENTRY}.wav';
  [bits_per_second, bits_per_sample, num_bits, num_samples, SNR, DEV] = codec(filename_in, filename_out, ${PREDICTOR}, ${QUALITY}, ${ENTRY});
  "
soxi "${FILE%%.wav}_32k_32bit_ZDA_Q${QUALITY}-E${ENTRY}.wav"

octave  -q --eval "
  graphics_toolkit qt;
  fs = 32000;
  signals = audioread('${FILE%%.wav}_32k_32bit.wav');
  signals_opus = audioread('${FILE%%.wav}_opus${OPUSRATE}_32k_32bit.wav');
  signals_zda = audioread('${FILE%%.wav}_32k_32bit_ZDA_Q${QUALITY}-E${ENTRY}.wav');
  for i=1:size(signals,2)
    signal = signals(:,i);
    signal_opus = signals_opus(:,i);
    signal_zda = signals_zda(:,i);

    figure('Position',[0 0 1600 800]);
    subplot(4,2,1);
    plot(signal);
    hold on;
    plot(signal_opus);
    xlabel('samples'); ylabel('amplitude');
    title('OPUS');
    subplot(4,2,3);
    imagesc(log_mel_spectrogram(signal_opus,fs,10,25,[20 16000]),[-100 0]); axis xy; colorbar;
    xlabel('10ms frame-shift'); ylabel('Mel-bands');
    title('OPUS');    
    subplot(4,2,5);
    plot(signal_opus-signal);ylim([-0.1 0.1]);
    xlabel('samples'); ylabel('amplitude');
    title('OPUS difference');
    subplot(4,2,7);
    imagesc(log_mel_spectrogram(signal_opus-signal,fs,10,25,[20 16000]),[-100 0]); axis xy; colorbar;
    xlabel('10ms frame-shift'); ylabel('Mel-bands');
    title('OPUS difference');
    subplot(4,2,2);
    plot(signal);
    hold on;
    plot(signal_zda);
    xlabel('samples'); ylabel('amplitude');
    title('ZDA');
    subplot(4,2,4);
    imagesc(log_mel_spectrogram(signal_zda,fs,10,25,[20 16000]),[-100 0]); axis xy; colorbar;
    xlabel('10ms frame-shift'); ylabel('Mel-bands');
    title('ZDA');
    subplot(4,2,6);
    plot(signal_zda-signal);ylim([-0.1 0.1]);
    xlabel('samples'); ylabel('amplitude');
    title('ZDA difference');
    subplot(4,2,8);
    imagesc(log_mel_spectrogram(signal_zda-signal,fs,10,25,[20 16000]),[-100 0]); axis xy; colorbar;
    xlabel('10ms frame-shift'); ylabel('Mel-bands');
    title('ZDA difference');
    set(gcf,'PaperUnits','inches','PaperPosition',[0 0 16 8].*1.4);
    print('-dpng','-r300',sprintf('${FILE%%.wav}_opus${OPUSRATE}_ZDA_Q${QUALITY}-E${ENTRY}_comparsion_c%i.png',i));
  end
  "
