# This file is part of the ZDAC reference implementation
# Author (2020) Marc René Schädler (suaefar@googlemail.com)

close all
clear
clc

graphics_toolkit qt;

% Assume 32kHz input with arbitrary precision (double float)
fs = 32000;
quality = 0; % Steers width of the masking threshold filters (0 default, probably useful values -5..1)
predictor = 3; % 0 none, 1 identity, 2 bilinear, 3 linear prediction
entry = 8; % period of entry points in ms

% Generate a stimulus: Vary frequency and level over time
level = [0 -20]; % dB
period = [1/2000 1/2]; % 16Hz to 16000kHz
signal = (10.^(linspace(level(1),level(2),fs/8)./20).*sin(2.*pi*cumsum(linspace(period(1),period(2),fs/8)))).';

%% Add some noise (to see how the birate reduces)
noiselevel = -90 % dB full-scale
noise = 2.*(rand(size(signal))-0.5);
noise = noise./rms(noise) .* 10.^(noiselevel./20);
signal = signal + noise;

% Only use blocks of 32 samples for later alignment in bitmap
signal = signal(1:floor(numel(signal)/32).*32);

audiowrite('orginal.wav',signal,fs,'BitsPerSample',32);

% Reference: Quantization with 16 bits
audiowrite('reference.wav',signal,fs,'BitsPerSample',16);
signal_ref = audioread('reference.wav');
audiowrite('reference.wav',signal,fs,'BitsPerSample',32);
bits_per_second_ref = 16.*fs


% Zero-delay audio codec (ZDAC)
%% ENCODER
[message controlcodes bits amplitude_tracker quantnoise_tracker exponent spectral_energy debug_message] = zdaenc(signal, fs, predictor, quality, entry);

num_samples = size(signal,1);
num_bits = numel(message);
num_significant_bits = sum(bits(controlcodes==0));
num_entry_bits = sum(bits(controlcodes==1));
num_exponent_bits = sum(bits(controlcodes==2));
num_codebook_bits = sum(bits(controlcodes==3));
bits_per_sample = num_bits./num_samples;
bits_per_second = bits_per_sample.*fs;

printf('%.1f %.3f %i %i/%i/%i/%i/%i %.1f %.1f\n',bits_per_second,bits_per_sample,num_samples,num_bits,num_significant_bits,num_entry_bits,num_exponent_bits,num_codebook_bits);

figure('Position',[0 0 1600 800]);
subplot(2,2,1);
plot(controlcodes);
ylim([-1 4]);
grid on;
title('Controlcode: 0 significant, 1 entry, 2 exponent, 3 codebook, 4 stop');
subplot(2,2,2);
bar([0 1 2 3 4],log10(histc(controlcodes,[0 1 2 3 4])));
yticks(log10(2.^(0:1:15)));
yticklabels(2.^(0:1:15));
xticklabels({'significant','entry','exponent','codebook','stop'});
grid on;
title('Controlcode: Absolute frequency')
subplot(2,2,3);
plot(bits);
ylim([-1 33]);
grid on;
title('Controlcode bits')
subplot(2,2,4);
bar(log10(histc(bits,[0:32])));
yticks(log10(2.^(0:1:15)));
yticklabels(2.^(0:1:15));
grid on;
title('Controlcode bits: Absolute frequency');
drawnow;

linecolors = lines(7);
zerodimfactor = 0.9;
colors= [
  linecolors(3,:).*zerodimfactor;
  linecolors(3,:);
  (linecolors(3,:)+[0 0.15 0]).*zerodimfactor;
  (linecolors(3,:)+[0 0.15 0]);
  linecolors(7,:).*zerodimfactor;
  linecolors(7,:);
  linecolors(1,:).*zerodimfactor;
  linecolors(1,:);
  linecolors(4,:).*zerodimfactor;
  linecolors(4,:);
  [0.5 0.5 0.5]
];

figure('Position',[0 0 1600 800]);
debug_message_padded = [debug_message,11.*ones(1,numel(signal)*16-numel(debug_message))];
bitmap = reshape(debug_message_padded,128,[])+3;
image(bitmap); axis image;
colormap(colors);
grid on
xticks(0:50:size(bitmap,2));
yticks(0:16:size(bitmap,1));
ylabel('bit number');
title('Coloured bitmap: yellow/orange - significant, red - entry, blue - exponent, purple - codebook'); 
drawnow;


%% DECODER
signal_reconst = zdadec(message, fs, predictor);

audiowrite('reconstructed.wav',signal_reconst,fs,'BitsPerSample',32);

quantnoise_ref = signal-signal_ref;
quantnoise = signal-signal_reconst;

figure('Position',[0 0 1600 800]);
subplot(4,1,1);
plot(signal);
hold on;
plot(signal_ref);
plot(quantnoise_ref);
legend({'Original' 'Reconstructed' 'Difference'});
ylabel('Amplitude');
title('Reference 16 bit/sample');
subplot(4,1,2);
plot(signal);
hold on;
plot(signal_reconst);
plot(quantnoise);
legend({'Original' 'Reconstructed' 'Difference'});
ylabel('Amplitude');
title('ZDAC')
subplot(4,1,3);
plot(10*log10(max(spectral_energy,[],1)));
ylim([-100 0]);
ylabel('Energy / dB');
title('Maximum of spectral energy');
subplot(4,1,4);
plot(amplitude_tracker);
hold on;
plot(quantnoise_tracker);
hold on;
plot(exponent);
legend({'Amplitude' 'Quantnoise' 'Exponent'});
ylabel('log2(amplitude)');
title('Tracker');

