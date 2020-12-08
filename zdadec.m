# This file is part of the ZDAC reference implementation
# Author (2020) Marc René Schädler (suaefar@googlemail.com)

function signal = zdadec(message, fs, num_channels)

%% SHARED PART
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

% Define variables which represent the state of the decoder
sample = zeros(1,num_channels,'int32'); % Current sample value in encoder
exponent = zeros(1,num_channels,'int32'); % Current exponent value
codebook = zeros(1,num_channels,'int32'); % Select codebook
significant = zeros(1,num_channels,'int32'); % Current significant value
residue = zeros(1,num_channels,'int32'); % Current residual value
sample_decoded = zeros(32,num_channels,'int32'); % Predicted sample value in decoder
sample_predicted = zeros(1,num_channels,'int32'); % Predicted sample value in decoder

% Maximum predictor context 
max_predictor_context = round(1 .* fs./1000);

%% DECODER PART

% Load decoding trees and codebooks
codebook_cache_file = 'codebook.bin';
load(codebook_cache_file);

message = logical(message); % Make sure we only have bits
num_bits = numel(message);
message_pointer = int32(0); % Pointer for last read bit
signal_buffer = nan(ceil(num_bits/2),num_channels,'single'); % Two bits per sample is minimum
signal_pointer = 0; % Pointer for last written sample

% Initialize variables
controlcode_decode = int32(2.^(2-1:-1:0));
sample_decode = int32(2.^(sample_alphabet_bits-1:-1:0));
exponent_decode = int32(2.^(exponent_alphabet_bits-1:-1:0));
significant_decode = int32(2.^(significant_alphabet_bits-1:-1:0));
codebook_decode = int32(2.^(codebook_alphabet_bits-1:-1:0));

% Load initial tree
tree_traverse = codebooks{1}{3};

% Reset predictor
sample_predicted = zeros(1,num_channels,'int32');

% Start with channel 1
channel = 1;

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
            % Reset predictor
            sample_predicted = zeros(1,num_channels,'int32');
            
            % Get corresponding bits
            for j=1:num_channels
              exponent_bits = int32(message(message_pointer+1:message_pointer+exponent_alphabet_bits));
              message_pointer = message_pointer + exponent_alphabet_bits;
              codebook_bits = int32(message(message_pointer+1:message_pointer+codebook_alphabet_bits));
              message_pointer = message_pointer + codebook_alphabet_bits;

              % Decode values
              exponent(j) = exponent_alphabet(1+sum(exponent_bits.*exponent_decode,'native'));
              codebook(j) = codebook_alphabet(1+sum(codebook_bits.*codebook_decode,'native'));
              
              % Start with channel 1
              channel = 1;
              last_entry_sample = signal_pointer;
            end

          case controlcode_exponent
            % Get corresponding bits
            exponent_bits = int32(message(message_pointer+1:message_pointer+exponent_alphabet_bits));
            message_pointer = message_pointer + exponent_alphabet_bits;

            % Decode values
            exponent(channel) = exponent_alphabet(1+sum(exponent_bits.*exponent_decode,'native'));

          case controlcode_codebook
            % Get corresponding bits
            codebook_bits = int32(message(message_pointer+1:message_pointer+codebook_alphabet_bits));
            message_pointer = message_pointer + codebook_alphabet_bits;
            
            % Decode values
            codebook(channel) = codebook_alphabet(1+sum(codebook_bits.*codebook_decode,'native'));

          case controlcode_stop
            break;
            
          otherwise
            error('unknown control code')
        end
      otherwise
        % Save value and read data for next channel
        residue(channel) = leave;
        channel += 1;
    end

    if channel > num_channels
      % Get the predicted significant value with the (possibly changed) current exponent
      significant_predicted = sample_predicted ./ 2.^exponent;
      significant_predicted = limit(significant_predicted,significant_factor.*[-1 1]);
   
      % Determine significant    
      significant = significant_predicted + residue;
        
      % Reconstruct signal from updated decoder data for next prediction
      sample_decoded = [sample_decoded(2:end,:); significant .* 2.^exponent];
      predictor_context = double(sample_decoded(max(end-(signal_pointer-last_entry_sample),1):end,:));    
      for j=1:num_channels
        sample_predicted(j) = int32(predictor(predictor_context(:,j)));
      end
      
      % Reconstruct sampled signal
      sample_value = double(sample_decoded(end,:))./double(sample_factor);
        
      % Write reconstructed sample value to signal buffer
      signal_buffer(signal_pointer+1,:) = sample_value;
      signal_pointer = signal_pointer + 1;   
      
      % Start again with channel 1
      channel = 1;
    end  
    
    tree_traverse = codebooks{1 + codebook(channel) - codebook_alphabet(1)}{3};
  end
end
signal = signal_buffer(1:signal_pointer,:);
end
