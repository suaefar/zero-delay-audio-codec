# This file is part of the ZDAC reference implementation
# Author (2020) Marc René Schädler (suaefar@googlemail.com)

function [bits_per_second, bits_per_sample, num_bits, num_samples, SNR, DEV] = codec(filename_in, filename_out, quality, entry)
  [signal, fs] = audioread(filename_in);
  signal_reconst = zeros(size(signal));
  num_channels = size(signal,2);
  for i=1:num_channels
    printf('Encode channel %i\n',i);
    [message bits] = zdaenc(signal(:,i), fs, quality, entry);
    printf('Write zda binary\n');
    zda_filename = [filename_out sprintf('_c%i.zda',i)];
    writebinary(zda_filename, [dec2bin(fs,24)=='1' message]);
    num_samples = numel(signal(:,i));
    num_bits = numel(message);
    num_significant_bits = sum(bits(1,:));
    num_entry_bits = sum(bits(2,:));
    num_exponent_bits = sum(bits(3,:));
    num_codebook_bits = sum(bits(4,:));
    num_stop_bits = sum(bits(5,:));
    bits_per_sample = num_bits./num_samples;
    bits_per_second = bits_per_sample.*fs;
    printf('Read zda binary\n');
    message = readbinary(zda_filename);
    fs = bin2dec('01'(1+message(1:24)));
    message = message(1+24:end);
    printf('Decode channel %i\n',i);
    signal_reconst(:,i) = zdadec(message, fs);
    SNR = 20*log10(rms(signal(:,i) - signal_reconst(:,i))./rms(signal(:,i)));
    DEV = 20*log10(max(abs(signal(:,i)-signal_reconst(:,i))));
    printf('RESULT: %s %i %.1f %.1f %.1f %.3f %i %i/%i/%i/%i/%i %.1f %.1f\n',strrep(filename_out,' ','_'),i,quality,entry,bits_per_second,bits_per_sample,num_samples,num_bits,num_significant_bits,num_entry_bits,num_exponent_bits,num_codebook_bits,SNR,DEV);
  end
  audiowrite(filename_out,signal_reconst,fs,'BitsPerSample',32);
end
