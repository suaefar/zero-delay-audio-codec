# This file is part of the ZDAC reference implementation
# Author (2020) Marc René Schädler (suaefar@googlemail.com)

close all
clear
clc

graphics_toolkit qt;

% Assume 32kHz input with arbitrary precision (double float)
fs = 44100;
quality = 0; % Steers width of the masking threshold filters (0 default, probably useful values -5..1)
entry = 2.5; % period of entry points in ms
rate = 250; % soft-limit rate

% Generate a stimulus: Vary frequency and level over time
level = [0 -20]; % dB
period = [1/2000 1/2]; % 16Hz to 16000kHz
signal = (10.^(linspace(level(1),level(2),fs/8)./20).*sin(2.*pi*cumsum(linspace(period(1),period(2),fs/8)))).';

%% Add some noise (to see how the birate reduces)
noiselevel = -90; % dB full-scale
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

% Zero-delay audio codec (ZDAC)
%% ENCODER
num_samples = size(signal,1);
num_channels = size(signal,2);
[message bits amplitude_tracker quantnoise_tracker exponent spectral_energy debug_message] = zdaenc(signal, fs, quality, entry, rate);

num_bits = numel(message);
num_significant_bits = sum(bits(1,:));
num_entry_bits = sum(bits(2,:));
num_exponent_bits = sum(bits(3,:));
num_codebook_bits = sum(bits(4,:));
num_stop_bits = sum(bits(5,:));
bits_per_sample = num_bits./num_samples;
bits_per_second = bits_per_sample.*fs;

printf('%.1f %.3f %i %i/%i/%i/%i/%i\n',bits_per_second,bits_per_sample,num_samples,num_bits,num_significant_bits,num_entry_bits,num_exponent_bits,num_codebook_bits);

writebinary('demo.zda', [dec2bin(fs,24)=='1' dec2bin(num_channels,8)=='1' message]);
filesize = stat('demo.zda').size;
printf('binary data written to demo.zda (%d bytes)\n',filesize);

% Colorscheme
linecolors = lines(7);
zerodimfactor = 0.9;
colors = [
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
  linecolors(5,:).*zerodimfactor;
  linecolors(5,:);
  [0.5 0.5 0.5];
];

figure('Position',[0 0 1600 800]);
subplot(2,3,[1 2 3]);
plot(bits(1,:),'color',colors(2,:));
hold on;
plot(bits(2,:),'color',colors(6,:));
plot(bits(3,:),'color',colors(8,:));
plot(bits(4,:),'color',colors(10,:));
plot(bits(5,:),'color',colors(12,:));
ylabel('Bit');
xlabel('Sample');
grid on;
title('Contol codes');
legend({'significant' 'entry' 'exponent' 'codebook' 'stop'});

subplot(2,3,4);
bar(log10(histc(sum(bits),[0:40],2)));
yticks(log10(2.^(0:1:15)));
yticklabels(2.^(0:1:15));
ylabel('Absolute frequency');
xlabel('Bit per sample');
grid on;
title('Absolute frequencies of bits per sample');

subplot(2,3,5);
bar([0 1 2 3 4],log10(sum(bits>0,2)));
yticks(log10(2.^(0:1:15)));
yticklabels(2.^(0:1:15));
xticklabels({'significant','entry','exponent','codebook','stop'});
ylabel('Absolute frequency');
xlabel('Control code');
grid on;
title('Control codes: Absolute frequency')

subplot(2,3,6);
bar([0 1 2 3 4],log10(sum(bits,2)));
yticks(log10(2.^(0:1:20)));
yticklabels(2.^(0:1:20));
xticklabels({'significant','entry','exponent','codebook','stop'});
ylabel('Absolute frequency');
xlabel('Control code');
grid on;
title('Control codes: Cumulative bits')
drawnow;

figure('Position',[0 0 1600 800]);
debug_message_padded = [debug_message,11.*ones(1,numel(signal)*16-numel(debug_message))];
bitmap = reshape(debug_message_padded,128,[])+3;
image(bitmap); axis image;
colormap(colors);
grid on
xticks(0:50:size(bitmap,2));
yticks(0:16:size(bitmap,1));
ylabel('bit number');
title('Coloured bitmap: yellow/orange - significant, red - entry, blue - exponent, purple - codebook, green - stop'); 
drawnow;

printf('clear message and fs\n');
clear message fs

%% DECODER
message = readbinary('demo.zda');
fs = bin2dec('01'(1+message(1:24)));
num_channels = bin2dec('01'(1+message(25:32)));
message = message(33:end);
printf('%i message bits read from demo.zda\n',numel(message));

signal_reconst = zdadec(message, fs, num_channels);

audiowrite('reconstructed.wav',signal_reconst,fs,'BitsPerSample',32);

signal = signal(:,1);
signal_ref = signal_ref(:,1);
signal_reconst = signal_reconst(:,1);

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

