# This file is part of the ZDAC reference implementation
# Author (2020) Marc René Schädler (suaefar@googlemail.com)

function [message debug_controlcodes debug_bits debug_amplitude_tracker debug_quantnoise_tracker debug_exponent debug_spectral_energy debug_message] = zdaenc(signal, fs, predictor, quality, entry)

if nargin() < 3
  predictor = 3;
end

if nargin() < 4
  quality = 0;
end

if nargin() < 5
  entry = 16;
end

assert(size(signal,2)==1,'only one channel audio supported')

%% SHARED PART
predictors = {@predictor_zero @predictor_simple @predictor_linear @predictor_lpc};
predict = predictors{predictor+1};

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

% Control code alphabet
controlcode_alphabet = {'entry' 'exponent' 'codebook' 'stop'};
controlcode_id_entry = 1;
controlcode_id_exponent = 2;
controlcode_id_codebook = 3;
controlcode_id_stop = 4;

% Enable decoder to start decoding every entry_period samples
entry_period = round(entry .* (fs./1000)); % ms

% Define control code tree
control_tree = {{'entry' 'exponent'} {'codebook' 'stop'}};
[control_symbols control_codes] = gencodebook(control_tree);

% Define variables which represent the state of the decoder
sample = int32(0); % Current sample value (20bit)
exponent = int32(0); % Current exponent value
significant = int32(0); % Current significant value
residue = int32(0); % Current residual value
codebook = int32(0); % Select codebook

% Build huffman trees and codebooks
codebook_cache_file = sprintf('codebooks-%i.bin',significant_alphabet_bits);
if ~exist(codebook_cache_file)
  % Generate codebooks for different residual rms values
  codebooks = cell(numel(codebook_alphabet),1);
  for i=1:numel(codebook_alphabet)
    residue_alphabet_prob = normpdf(-residue_factor:residue_factor,0,2.^-double(codebook_alphabet(i)).*double(residue_factor));
    residue_alphabet_freq = max(0.05,fs.*residue_alphabet_prob./sum(residue_alphabet_prob));
    huffman_tree = huffman(residue_alphabet_freq,int32(-residue_factor:residue_factor));
    [huffman_symbols, huffman_codes] = gencodebook(huffman_tree);
    huffman_symbols = [huffman_symbols{:}];
    [~, vidx] = sort(huffman_symbols);
    huffman_symbols = huffman_symbols(vidx);
    huffman_codes = huffman_codes(vidx);
    codebooks{i} = {huffman_symbols huffman_codes huffman_tree};
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
exponent_default = exponent; % Default codebook for entry points
codebook_default = codebook; % Default codebook for entry points
exponent_last = exponent_default; % Reference to check for updates
codebook_proposed = codebook_default; % Reference to check for updates
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
residual_update = 0.1;
spectral_update = 0.1;

% Load default codebook
[huffman_symbols huffman_codes huffman_tree] = codebooks{1 + codebook_default - codebook_alphabet(1)}{:};

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
debug_controlcodes = zeros(1,2.*num_samples);
debug_bits = zeros(1,2.*num_samples);
debug_message_buffer = zeros(size(message_buffer));
debug_controlcodes_pointer = 0;
debug_amplitude_tracker = zeros(1,num_samples);
debug_quantnoise_tracker = zeros(1,num_samples);
debug_exponent = zeros(1,num_samples);
debug_spectral_energy = zeros(num_bands,num_samples);

for i=1:num_samples
  % Get the information we want to transmit
  sample_value = limit(double(signal(i)),[-1 1]);
  
  % Spectral energy analysis
  filter_status(:,1) = sample_value .* b0 + filter_status(:,1) .* a1;
  filter_status(:,2) = filter_status(:,1) + filter_status(:,2) .* a1;
  filter_status(:,3) = filter_status(:,2) + filter_status(:,3) .* a1;
  filter_status(:,4) = filter_status(:,3) + filter_status(:,4) .* a1;
  spectral_energy = spectral_energy .* (1-spectral_update) + abs(filter_status(:,4)).^2 .* spectral_update; ;
  debug_spectral_energy(:,i) = spectral_energy;
  
  % Encode the current sample
  sample = int32(round(sample_value.*double(sample_factor)));
   
  % Insert entry point if requested
  if mod(i-1,entry_period) < 0.5
    %% Generate ENTRY sample 
    
    % Compile raw sample bits
    sample_bits = dec2bin(sample+sample_factor,sample_alphabet_bits) == '1';
    insert_bits = [false control_codes{controlcode_id_entry} sample_bits];

    % Now sync the state with the decoder

    % Set default exponent
    exponent = exponent_default;
    exponent_last = exponent_default;
    
    % Set default codebook
    codebook = codebook_default;
    codebook_proposed = codebook_default;
    
    % Use the announced codebook   
    [huffman_symbols huffman_codes huffman_tree] = codebooks{1 + codebook - codebook_alphabet(1)}{:};
    
    % Reset predictor
    predict();
    sample_predicted = int32(0);
    
    % Insert the compiled bits into the message
    message_buffer(message_pointer+1:message_pointer+numel(insert_bits)) = insert_bits;
    debug_message_buffer(message_pointer+1:message_pointer+numel(insert_bits)) = double(insert_bits)+2.*controlcode_id_entry;
    
    message_pointer = message_pointer + numel(insert_bits);
    debug_controlcodes(debug_controlcodes_pointer+1) = controlcode_id_entry;
    debug_bits(debug_controlcodes_pointer+1) = numel(insert_bits);
    debug_controlcodes_pointer = debug_controlcodes_pointer + 1;
  else
    %% ENCODE significant and (optionally) update decoder state
    % Track maximum of log sample amplitude   
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
   
    % Check if we need to inform about a new exponent
    if exponent_proposed > exponent_last  || (exponent_proposed < exponent_last && exponent_proposed - exponent_ideal > 0.75)
      % Use proposed exponent
      exponent = exponent_proposed;

      % Compile exponent bits
      exponent_bits = dec2bin(exponent-exponent_alphabet(1),exponent_alphabet_bits)=='1';
      insert_bits = [false control_codes{controlcode_id_exponent} exponent_bits];

      % Remember current exponent
      exponent_last = exponent;
      
      % Insert the compiled bits into the message
      message_buffer(message_pointer+1:message_pointer+numel(insert_bits)) = insert_bits;
      debug_message_buffer(message_pointer+1:message_pointer+numel(insert_bits)) = double(insert_bits)+2.*controlcode_id_exponent;
      message_pointer = message_pointer + numel(insert_bits);
      debug_controlcodes(debug_controlcodes_pointer+1) = controlcode_id_exponent;
      debug_bits(debug_controlcodes_pointer+1) = numel(insert_bits);
      debug_controlcodes_pointer = debug_controlcodes_pointer + 1;
    end

    % Calculate significant
    debug_exponent(i) = exponent;
    dither_value = (rand(1)-0.5).*(2.^(exponent-1)-1);
    significant = (sample+dither_value) ./ 2.^exponent;
    
    % Guess best codebook based on recent residual energy
    codebook_proposed = int32(round(-log2(sqrt(residual_energy))));
    codebook_proposed = limit(codebook_proposed,codebook_alphabet([1 end]));
    
    % Check if we should change the codebook (with hysteresis)
    if codebook_proposed < codebook || (codebook_proposed > codebook && -log2(sqrt(residual_energy)) > double(codebook)+0.75)
      % Use proposed codebook
      codebook = codebook_proposed;
      
      % Compile codebook bits
      codebook_bits = dec2bin(codebook-codebook_alphabet(1),codebook_alphabet_bits)=='1';
      insert_bits = [false control_codes{controlcode_id_codebook} codebook_bits];

      % Use the announced codebook
      [huffman_symbols huffman_codes huffman_tree] = codebooks{1 + codebook - codebook_alphabet(1)}{:};

      % Insert the compiled bits into the message
      message_buffer(message_pointer+1:message_pointer+numel(insert_bits)) = insert_bits;
      debug_message_buffer(message_pointer+1:message_pointer+numel(insert_bits)) = double(insert_bits)+2.*controlcode_id_codebook;
      message_pointer = message_pointer + numel(insert_bits);
      debug_controlcodes(debug_controlcodes_pointer+1) = controlcode_id_codebook;
      debug_bits(debug_controlcodes_pointer+1) = numel(insert_bits);
      debug_controlcodes_pointer = debug_controlcodes_pointer + 1;
    end
        
    % Get the predicted significant value with the (possibly changed) current exponent   
    significant_predicted = sample_predicted ./ 2.^exponent;
    significant_predicted = limit(significant_predicted,significant_factor.*[-1 1]);
   
    % Determine residue 
    residue = significant - significant_predicted;
    
    % Update residual energy
    residual_energy = residual_energy .* (1-residual_update) + (double(residue)./double(residue_factor)).^2 .* residual_update;

    % Compile bits
    insert_bits = [true huffman_codes{1+residue+residue_factor}];
   
    % Insert the compiled bits into the message
    message_buffer(message_pointer+1:message_pointer+numel(insert_bits)) = insert_bits;
    debug_message_buffer(message_pointer+1:message_pointer+numel(insert_bits)) = double(insert_bits)-2.*mod(i,2);
    message_pointer = message_pointer + numel(insert_bits);
    debug_controlcodes(debug_controlcodes_pointer+1) = 0;
    debug_bits(debug_controlcodes_pointer+1) = numel(insert_bits);
    debug_controlcodes_pointer = debug_controlcodes_pointer + 1;
      
    % Reconstruct signal from updated decoder data for next prediction
    sample_decoded = significant .* 2.^exponent;
    
    % Predict next sample
    sample_predicted = predict(sample_decoded);
    sample_predicted = int32(sample_predicted);
  end
end
% Tell the decoder to stop
insert_bits = [false control_codes{controlcode_id_stop}];
% Insert the compiled bits into the message
message_buffer(message_pointer+1:message_pointer+numel(insert_bits)) = insert_bits;
message_pointer = message_pointer + numel(insert_bits);
debug_controlcodes(debug_controlcodes_pointer+1) = controlcode_id_stop;
debug_bits(debug_controlcodes_pointer+1) = numel(insert_bits);
debug_controlcodes_pointer = debug_controlcodes_pointer + 1;

message = message_buffer(1:message_pointer);
debug_message = debug_message_buffer(1:message_pointer);

debug_controlcodes = debug_controlcodes(1:debug_controlcodes_pointer);
debug_bits = debug_bits(1:debug_controlcodes_pointer);

message_bits = numel(message);
message_bits_per_sample = message_bits./num_samples;
message_bits_per_second = message_bits_per_sample.*fs;

% Some statistics 
message_bits = numel(message)
printf('\nMessage encoded in %i bits, thats %.3f kbits per second and %.3f bits per sample\n',message_bits,message_bits_per_second./1000,message_bits_per_sample);
end
