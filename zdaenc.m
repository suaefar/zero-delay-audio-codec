# This file is part of the ZDAC reference implementation
# Author (2020) Marc René Schädler (suaefar@googlemail.com)

function [message debug_bits debug_amplitude_tracker debug_quantnoise_tracker debug_exponent debug_spectral_energy debug_message] = zdaenc(signal, fs, quality, entry)

if nargin() < 3
  quality = 0;
end

if nargin() < 4
  entry = 8;
end

assert(size(signal,2)==1,'only one channel audio supported')

%% SHARED PART
% Use LPC predictor
predict = @predictor_lpc;

% Alphabet used for significant quantization
significant_alphabet_bits = int32(12);
significant_min_bits = 2;
significant_factor = 2.^(significant_alphabet_bits-1)-1;
residue_factor = 2.*significant_factor;

%% Define integer symbol alphabets
% Alphabet used for exponent quantization
exponent_alphabet = int32(0:31);
exponent_alphabet_bits = int32(ceil(log2(numel(exponent_alphabet))));

% Alphabet used for sample quantization
sample_factor = 2.^(20-1)-1;
sample_alphabet_bits = ceil(log2(sample_factor.*2));

% Alphabet used for codebooks
codebook_alphabet = int32(0:13);
codebook_alphabet_bits = int32(ceil(log2(numel(codebook_alphabet))));

% Control codes
controlcode_prefixbits = 4;
controlcode = [true(1,controlcode_prefixbits-1) false];
controlcode_entry = 0;
controlcode_exponent = 1;
controlcode_codebook = 2;
controlcode_stop = 3;

% Enable decoder to start decoding every entry_period samples
entry_period = round(entry .* (fs./1000)); % ms

% Define variables which represent the state of the decoder
sample = int32(0); % Current sample value (20bit)
exponent = int32(0); % Current exponent value
significant = int32(0); % Current significant value
residue = int32(0); % Current residual value
codebook = int32(0); % Select codebook

% Build decoding trees and codebooks
codebook_cache_file = 'codebook.bin';
if ~exist(codebook_cache_file)
  % Generate codebooks for different residual rms values
  codebooks = cell(numel(codebook_alphabet),1);
  for i=1:numel(codebook_alphabet)
    residue_alphabet_prob = normpdf(-residue_factor:residue_factor,0,2.^-double(codebook_alphabet(i)).*double(residue_factor));
    residue_alphabet_freq = max(0.000002,residue_alphabet_prob./sum(residue_alphabet_prob));
    frequencies = residue_alphabet_freq;
    alphabet = num2cell(int32(-residue_factor:residue_factor));
    [~, sidx] = sort(frequencies,'descend');
    frequencies_s = frequencies(sidx);
    alphabet_s = alphabet(sidx);
    % Generate decoding tree with reserved code for control
    tree = reserved_huffman(frequencies_s, alphabet_s, controlcode_prefixbits-1);
    [symbols, codes] = gencodebook(tree);
    controlid = find(strcmp(symbols,'control'));
    symbols(controlid) = [];
    codes(controlid) = [];
    symbols = [symbols{:}];
    [~, sidx] = sort(symbols);
    symbols = symbols(sidx);
    codes = codes(sidx);
    codebooks{i} = {symbols codes tree};
  end
  save('-binary', codebook_cache_file, 'codebooks');
else
  load(codebook_cache_file);
end

% Time constants for signal amplitude tracking
amplitude_decrease = 0.1 ./ (fs./1000); % halfing in 10 ms
amplitude_hold = 10 .* (fs./1000); % 10 ms

% Time constants for quantization noise tracking
quantnoise_increase = 1 ./ (fs./1000); % doubling in 1 ms
quantnoise_hold = 1 .* (fs./1000); % 1 ms

%% ENCODER PART
message_buffer = zeros(1,round(32.*numel(signal)),'logical'); % Buffer for bits
message_pointer = int32(0); % Pointer for last written bit

% Initialize variables
exponent_last = exponent; % Reference to check for updates
num_samples = numel(signal);
sample_value = 0;
sample_decoded = int32(0);
sample_predicted = int32(0);
dither_value = int32(0);
quantnoise_tracker = 0;
quantnoise_hold_counter = 0;
amplitude_tracker = 0;
amplitude_hold_counter = 0;
residual_energy = 0.1;
residual_update = 0.05;
spectral_update = 0.1;
update_entry = false;
update_exponent = false;
update_codebook = false;

% Analyis filters for dynamic quantization adaptation
quantnoise_model = rand(fs,1)-0.5;
[quantnoise_model_analysis, filter_centers, filter_coefficients, filter_bandwidths] = mel_gammatone_iir(quantnoise_model, fs, [64 16000], 1, 2 .* sqrt(2).^quality);
b0 = filter_coefficients(:,1);
a1 =  filter_coefficients(:,2);
num_bands = numel(filter_centers);
filter_status = zeros(num_bands,4);
spectral_energy = zeros(num_bands,1);
% Build a model of the quantization noise levels
quantnoise_model_levels = log2(sqrt(mean(abs(quantnoise_model_analysis).^2))).';

% Debug variables
debug_bits = zeros(5,num_samples);
debug_message_buffer = zeros(size(message_buffer));
debug_amplitude_tracker = zeros(1,num_samples);
debug_quantnoise_tracker = zeros(1,num_samples);
debug_exponent = zeros(1,num_samples);
debug_codebook = zeros(1,num_samples);
debug_spectral_energy = zeros(num_bands,num_samples);

for i=1:num_samples
  # Determine if its time to reset the predictor and send the entry information
  if mod(i-1,entry_period) < 0.5
    update_entry = true;
    % Reset predictor
    predict();
    sample_predicted = int32(0);
  else
    update_entry = false;
  end
  
  % Get the information we want to transmit
  sample_value = limit(double(signal(i)),[-1 1]);
  
  % Spectral energy analysis for the masking model
  filter_status(:,1) = sample_value .* b0 + filter_status(:,1) .* a1;
  filter_status(:,2) = filter_status(:,1) + filter_status(:,2) .* a1;
  filter_status(:,3) = filter_status(:,2) + filter_status(:,3) .* a1;
  filter_status(:,4) = filter_status(:,3) + filter_status(:,4) .* a1;
  spectral_energy = spectral_energy .* (1-spectral_update) + abs(filter_status(:,4)).^2 .* spectral_update; ;
  debug_spectral_energy(:,i) = spectral_energy;
  
  % Encode the current sample
  sample = int32(round(sample_value.*double(sample_factor)));
  
  % Track the maximum of log sample amplitude   
  amplitude_exponent = max(0,log2(double(abs(sample))));
  if amplitude_exponent > amplitude_tracker - amplitude_decrease
    amplitude_tracker = amplitude_exponent;
    amplitude_hold_counter = amplitude_hold;
  else
    if amplitude_hold_counter > 1
      amplitude_hold_counter = amplitude_hold_counter - 1;
    else
      amplitude_tracker = amplitude_tracker - amplitude_decrease;
    end
  end
  debug_amplitude_tracker(i) = amplitude_tracker;

  % Make sure that the significant is less than 1
  min_exponent = ceil(amplitude_tracker - log2(double(significant_factor)));
  % Make sure that the significant encodes significant_min_bits
  max_exponent = floor(amplitude_tracker - significant_min_bits);
    
  % Determine suitable exponent as minimum distance in bits between 
  % masked threshold and minimum quantization noise level
  masked_threshold = log2(sqrt(spectral_energy)) + log2(double(sample_factor));
  quantnoise_masked_distance = masked_threshold - quantnoise_model_levels;
  
  % Track minimum of suitable exponent
  quantnoise_exponent = max(0,min(quantnoise_masked_distance));
  if quantnoise_exponent < quantnoise_tracker + quantnoise_increase
    quantnoise_tracker = quantnoise_exponent;
    quantnoise_hold_counter = quantnoise_hold;
  else
    if quantnoise_hold_counter > 1
      quantnoise_hold_counter = quantnoise_hold_counter - 1;
    else
      quantnoise_tracker = quantnoise_tracker + quantnoise_increase;
    end
  end
  debug_quantnoise_tracker(i) = quantnoise_tracker;
  
  % Keep the exponent in that range
  exponent_ideal = max(min_exponent,min(quantnoise_tracker,max_exponent));
  exponent_proposed = int32(ceil(exponent_ideal));
  exponent_proposed = limit(exponent_proposed,exponent_alphabet([1 end]));
  
  % Check if we should use a new exponent
  if update_entry || exponent_proposed > exponent_last  || (exponent_proposed < exponent_last && exponent_proposed - exponent_ideal > 0.75)
    exponent = exponent_proposed;
    exponent_bits = dec2bin(exponent-exponent_alphabet(1),exponent_alphabet_bits)=='1';
    exponent_last = exponent;
    update_exponent = true;
  else
    update_exponent = false;
  end
  debug_exponent(i) = exponent;

  % Calculate significant with current exponent
  dither_value = (rand(1)-0.5).*(2.^(exponent-1)-1);
  significant = (sample+dither_value) ./ 2.^exponent;
      
  % Get the predicted significant value with the (possibly changed) current exponent   
  significant_predicted = sample_predicted ./ 2.^exponent;
  significant_predicted = limit(significant_predicted,significant_factor.*[-1 1]);
 
  % Determine residue and update residual energy
  residue = significant - significant_predicted;
  residual_energy = residual_energy .* (1-residual_update) + (double(residue)./double(residue_factor)).^2 .* residual_update;
  
  % Guess best codebook based on current residual energy
  codebook_proposed = int32(round(-log2(sqrt(residual_energy))));
  codebook_proposed = limit(codebook_proposed,codebook_alphabet([1 end]));
  
  % Check if we should change the codebook (with hysteresis)
  if update_entry || codebook_proposed < codebook || (codebook_proposed > codebook && -log2(sqrt(residual_energy)) > double(codebook)+0.75)
    codebook = max(0,codebook_proposed - 1.*int32(update_entry));
    codebook_bits = dec2bin(codebook-codebook_alphabet(1),codebook_alphabet_bits)=='1';
    [symbols codes tree] = codebooks{1 + codebook - codebook_alphabet(1)}{:};
    update_codebook = true;
  else
    update_codebook = false;
  end
  debug_codebook(i) = codebook;
  
  % Encode residual with current codebook
  residue_bits = codes{1+residue+residue_factor};

  % Reconstruct signal and predict next sample
  sample_decoded = significant .* 2.^exponent;
  sample_predicted = int32(predict(sample_decoded));
    
  %% Compile control bits
  if update_entry
    insert_bits = [controlcode dec2bin(controlcode_entry,2)=='1' exponent_bits codebook_bits];
    message_buffer(message_pointer+1:message_pointer+numel(insert_bits)) = insert_bits;
    debug_message_buffer(message_pointer+1:message_pointer+numel(insert_bits)) = double(insert_bits)+2.*(controlcode_entry+1);
    message_pointer += numel(insert_bits);
    debug_bits(2+controlcode_entry,i) = numel(insert_bits);
  else
    if update_exponent
      insert_bits = [controlcode dec2bin(controlcode_exponent,2)=='1' exponent_bits];
      message_buffer(message_pointer+1:message_pointer+numel(insert_bits)) = insert_bits;
      debug_message_buffer(message_pointer+1:message_pointer+numel(insert_bits)) = double(insert_bits)+2.*(controlcode_exponent+1);
      message_pointer += numel(insert_bits);
      debug_bits(2+controlcode_exponent,i) = numel(insert_bits);
    end
    if update_codebook
      insert_bits = [controlcode dec2bin(controlcode_codebook,2)=='1' codebook_bits];
      message_buffer(message_pointer+1:message_pointer+numel(insert_bits)) = insert_bits;
      debug_message_buffer(message_pointer+1:message_pointer+numel(insert_bits)) = double(insert_bits)+2.*(controlcode_codebook+1);
      message_pointer += numel(insert_bits);
      debug_bits(2+controlcode_codebook,i) = numel(insert_bits);
    end
  end
  
  % Compile residue bits
  insert_bits = residue_bits;
  message_buffer(message_pointer+1:message_pointer+numel(insert_bits)) = insert_bits;
  debug_message_buffer(message_pointer+1:message_pointer+numel(insert_bits)) = double(insert_bits)-2.*mod(i,2);
  message_pointer += numel(insert_bits);
  debug_bits(1,i) = numel(insert_bits);
end
% Tell the decoder to stop
insert_bits = [controlcode dec2bin(controlcode_stop,2)=='1'];
message_buffer(message_pointer+1:message_pointer+numel(insert_bits)) = insert_bits;
debug_message_buffer(message_pointer+1:message_pointer+numel(insert_bits)) = double(insert_bits)+2.*(controlcode_stop+1);
message_pointer += numel(insert_bits);
debug_bits(2+controlcode_stop,i) = numel(insert_bits);

message = message_buffer(1:message_pointer);
debug_message = debug_message_buffer(1:message_pointer);

message_bits = numel(message);
message_bits_per_sample = message_bits./num_samples;
message_bits_per_second = message_bits_per_sample.*fs;

% Some statistics 
message_bits = numel(message)
printf('\nMessage encoded in %i bits, thats %.3f kbits per second and %.3f bits per sample\n',message_bits,message_bits_per_second./1000,message_bits_per_sample);
end
