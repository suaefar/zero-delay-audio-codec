# This file is part of the ZDAC reference implementation
# Author (2020) Marc René Schädler (suaefar@googlemail.com)

function [bits_per_second, bits_per_sample, num_bits, num_samples, SNR, DEV] = codec(filename_in, filename_out, quality, entry)
  [signal, fs] = audioread(filename_in);
  signal_reconst = zeros(size(signal));
  num_channels = size(signal,2);
  [message bits] = zdaenc(signal, fs, quality, entry);
  printf('Write zda binary\n');
  zda_filename = [filename_out '.zda'];
  writebinary(zda_filename, [dec2bin(fs,24)=='1' dec2bin(num_channels,8)=='1' message]);
  num_samples = size(signal,1);
  num_channels = size(signal,2);
  num_bits = numel(message);
  num_significant_bits = sum(bits(1,:));
  num_entry_bits = sum(bits(2,:));
  num_exponent_bits = sum(bits(3,:));
  num_codebook_bits = sum(bits(4,:));
  num_stop_bits = sum(bits(5,:));
  bits_per_sample = num_bits./num_samples;
  bits_per_second = bits_per_sample.*fs;
  printf('RESULT: %s %d %i %.1f %.1f %.1f %.3f %i %i/%i/%i/%i/%i\n',strrep(filename_out,' ','_'),fs,num_channels,quality,entry,bits_per_second,bits_per_sample,num_samples,num_bits,num_significant_bits,num_entry_bits,num_exponent_bits,num_codebook_bits); 
  printf('Read zda binary\n');
  message = readbinary(zda_filename);
  fs = bin2dec('01'(1+message(1:24)));
  num_channels = bin2dec('01'(1+message(25:32)));
  message = message(33:end);
  signal_reconst = zdadec(message, fs, num_channels);
  audiowrite(filename_out,signal_reconst,fs,'BitsPerSample',32);
end
