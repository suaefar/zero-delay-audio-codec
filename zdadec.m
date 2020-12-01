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
controlcode_prefixbits = 3;
controlcode = [true(1,controlcode_prefixbits-1) false];
controlcode_entry = 0;
controlcode_exponent = 1;
controlcode_codebook = 2;
controlcode_stop = 3;

% Define variables which represent the state of the decoder
sample = int32(0); % Current sample value (20bit)
exponent = int32(0); % Current exponent value
significant = int32(0); % Current significant value
residue = int32(0); % Current residual value
codebook = int32(0); % Select codebook

% Load decoding trees and codebooks
codebook_cache_file = 'codebook.bin';
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
controlcode_decode = int32(2.^(2-1:-1:0));
sample_bits = zeros(1,sample_alphabet_bits,'logical');
sample_decode = int32(2.^(sample_alphabet_bits-1:-1:0));
exponent_bits = zeros(1,exponent_alphabet_bits,'logical');
exponent_decode = int32(2.^(exponent_alphabet_bits-1:-1:0));
significant_bits = zeros(1,significant_alphabet_bits,'logical');
significant_decode = int32(2.^(significant_alphabet_bits-1:-1:0));
codebook_bits = zeros(1,codebook_alphabet_bits,'logical');
codebook_decode = int32(2.^(codebook_alphabet_bits-1:-1:0));

% Load default codebook
[symbols codes tree] = codebooks{1 + codebook_default - codebook_alphabet(1)}{:};
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
      case 'control'
        % Get next two bits 
        controlcode_bits = int32(message(message_pointer+1:message_pointer+2));
        message_pointer = message_pointer + 2;
        
        % Decode control code
        controlcode = sum(controlcode_bits.*controlcode_decode,'native');
        
        switch controlcode
          case controlcode_entry
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
            [symbols codes tree] = codebooks{1 + codebook - codebook_alphabet(1)}{:};
            
            % Reset predictor
            predict();
            sample_predicted = int32(0);
            
            % Reconstruct sampled signal
            sample_value = double(sample)./double(sample_factor);
            
            % Write reconstructed sample value to signal buffer
            signal_buffer(signal_pointer+1) = sample_value;
            signal_pointer = signal_pointer + 1;   
            
          case controlcode_exponent
            % Get corresponding bits
            exponent_bits = int32(message(message_pointer+1:message_pointer+exponent_alphabet_bits));
            message_pointer = message_pointer + exponent_alphabet_bits;

            % Decode values
            exponent = exponent_alphabet(1+sum(exponent_bits.*exponent_decode,'native'));

          case controlcode_codebook
            % Get corresponding bits
            codebook_bits = int32(message(message_pointer+1:message_pointer+codebook_alphabet_bits));
            message_pointer = message_pointer + codebook_alphabet_bits;
            
            % Decode values
            codebook = codebook_alphabet(1+sum(codebook_bits.*codebook_decode,'native'));

            % Use the new codebook for further decoding
            [symbols codes tree] = codebooks{1 + codebook - codebook_alphabet(1)}{:};

          case controlcode_stop
            break;
          otherwise
            error('unknown control code')
        end
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
