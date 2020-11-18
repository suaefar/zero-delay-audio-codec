# This file is part of the ZDAC reference implementation
# Author (2020) Marc René Schädler (suaefar@googlemail.com)

function signal = zdadec(message, fs, predictor)

if nargin() < 3
  predictor = 3;
end

%% SHARED PART
predictors = {@predictor_zero @predictor_simple @predictor_linear @predictor_lpc};
predict = predictors{predictor+1};

% Alphabet used for significant quantization
significant_alphabet_bits = int32(12);
significant_min_bits = 4;
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
entry_period = 10 .* (fs./1000); % 10 ms

% Define control code tree
control_tree = {{'entry' 'exponent'} {'codebook' 'stop'}};
[control_symbols control_codes] = gencodebook(control_tree);

% Define variables which represent the state of the decoder
sample = int32(0); % Current sample value (20bit)
exponent = int32(0); % Current exponent value
significant = int32(0); % Current significant value
residue = int32(0); % Current residual value
codebook = int32(0); % Select codebook

% Load huffman trees and codebooks
codebook_cache_file = sprintf('codebooks-%i.bin',significant_alphabet_bits);
load(codebook_cache_file);

%% DECODER PART
message = logical(message); % Make sure we only have bits
num_bits = numel(message);
message_pointer = int32(0); % Pointer for last read bit
signal_buffer = nan(ceil(num_bits/2),1,'single'); % Two bits per sample is minimum
signal_pointer = int32(0); % Pointer for last written sample

% Initialize variables
exponent_default = exponent; % Default codebook for entry points
codebook_default = codebook; % Default codebook for entry points

sample_value = 0;
sample_decoded = int32(0);
current_bit = false;
sample_bits = zeros(1,sample_alphabet_bits,'logical');
sample_decode = int32(2.^(sample_alphabet_bits-1:-1:0));
exponent_bits = zeros(1,exponent_alphabet_bits,'logical');
exponent_decode = int32(2.^(exponent_alphabet_bits-1:-1:0));
significant_bits = zeros(1,significant_alphabet_bits,'logical');
significant_decode = int32(2.^(significant_alphabet_bits-1:-1:0));
codebook_bits = zeros(1,codebook_alphabet_bits,'logical');
codebook_decode = int32(2.^(codebook_alphabet_bits-1:-1:0));

% Load default codebook
[huffman_symbols huffman_codes huffman_tree] = codebooks{1 + codebook_default - codebook_alphabet(1)}{:};

% Prepare initial decoding tree
tree = {control_tree huffman_tree};
tree_traverse = tree;

% Reset predictor
predict();
sample_predicted = int32(0);
predictor_initialized = false;

% Debug variables

while message_pointer < num_bits
  % Read next bit and advance in tree
  message_pointer = message_pointer + 1;
  current_bit = message(message_pointer);
  leave = tree_traverse{current_bit+1};
  if iscell(leave)
    tree_traverse = leave;
  else
    switch (leave)
      case 'entry'
        % Get corresponding bits
        sample_bits = int32(message(message_pointer+1:message_pointer+sample_alphabet_bits));
        message_pointer = message_pointer + sample_alphabet_bits;
        
        % Decode values
        sample = sum(sample_bits.*sample_decode,'native') - sample_factor;
    
        % Set default exponent
        exponent = exponent_default;
    
        % Set default codebook
        codebook = codebook_default;
        
        % Use the new codebook for further decoding
        [huffman_symbols huffman_codes huffman_tree] = codebooks{1 + codebook - codebook_alphabet(1)}{:};
        tree = {control_tree huffman_tree};
        
        % Reset predictor
        predict();
        sample_predicted = int32(0);
        
        % Reconstruct sampled signal
        sample_value = double(sample)./double(sample_factor);
        
        % Write reconstructed sample value to signal buffer
        signal_buffer(signal_pointer+1) = sample_value;
        signal_pointer = signal_pointer + 1;   
        
      case 'exponent'
        % Get corresponding bits
        exponent_bits = int32(message(message_pointer+1:message_pointer+exponent_alphabet_bits));
        message_pointer = message_pointer + exponent_alphabet_bits;

        % Decode values
        exponent = exponent_alphabet(1+sum(exponent_bits.*exponent_decode,'native'));

      case 'codebook'
        % Get corresponding bits
        codebook_bits = int32(message(message_pointer+1:message_pointer+codebook_alphabet_bits));
        message_pointer = message_pointer + codebook_alphabet_bits;
        
        % Decode values
        codebook = codebook_alphabet(1+sum(codebook_bits.*codebook_decode,'native'));

        % Use the new codebook for further decoding
        [huffman_symbols huffman_codes huffman_tree] = codebooks{1 + codebook - codebook_alphabet(1)}{:};
        tree = {control_tree huffman_tree};

      case 'stop'
        break;
        
      otherwise
        residue = leave;
        
        % Get the predicted significant value with the (possibly changed) current exponent
        significant_predicted = sample_predicted ./ 2.^exponent;   
        significant_predicted = limit(significant_predicted,significant_factor.*[-1 1]);
   
        % Determine significant    
        significant = significant_predicted + residue;
        
        % Reconstruct diff signal from updated decoder data for next prediction
        sample_decoded = significant .* 2.^exponent;
        
        % Reconstruct sampled signal
        sample_value = double(sample_decoded)./double(sample_factor);
        
        % Write reconstructed sample value to signal buffer
        signal_buffer(signal_pointer+1) = sample_value;
        signal_pointer = signal_pointer + 1;   
        
        % Predict next sample_diff
        sample_predicted = int32(predict(sample_decoded));
    end
    tree_traverse = tree;
  end
end
signal = signal_buffer(1:signal_pointer);
end
