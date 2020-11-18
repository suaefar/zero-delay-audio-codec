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
entry = 10; % period of entry points in ms

% Generate a stimulus: Vary frequency and level over time
level = [0 -20]; % dB
period = [1/2000 1/2]; % 16Hz to 16000kHz
signal = (10.^(linspace(level(1),level(2),fs)./20).*sin(2.*pi*cumsum(linspace(period(1),period(2),fs)))).';

%% Bad bad noise
%signal = 2.*(rand(fs/4,1)-0.5);

audiowrite('orginal.wav',signal,fs,'BitsPerSample',32);

% Reference: Quantization with 16 bits
audiowrite('reference.wav',signal,fs,'BitsPerSample',16);
signal_ref = audioread('reference.wav');
audiowrite('reference.wav',signal,fs,'BitsPerSample',32);
bits_per_second_ref = 16.*fs


% Zero-delay audio codec (ZDAC)
%% ENCODER
[message controlcodes bits amplitude_tracker quantnoise_tracker exponent spectral_energy] = zdaenc(signal, fs, predictor, quality, entry);

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
title('Controlcode: 0 significant, 1 entry, 2 exponent, 3 codebook, 4 stop');
subplot(2,2,2);
bar([0 1 2 3 4],log10(histc(controlcodes,[0 1 2 3 4])));
yticks(log10(2.^(0:1:15)));
yticklabels(2.^(0:1:15));
xticklabels({'significant','entry','exponent','codebook','stop'});
title('Controlcode: Absolute frequency')
subplot(2,2,3);
plot(bits);
ylim([-1 33]);
title('Controlcode bits')
subplot(2,2,4);
bar(log10(histc(bits,[0:32])));
yticks(log10(2.^(0:1:15)));
yticklabels(2.^(0:1:15));
title('Controlcode bits: Absolute frequency');
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

