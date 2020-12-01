close all 
clear
clc

graphics_toolkit qt;

%alphabet    = {0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15};
%frequencies = [1  2  3  4  5  6  7  8  8  7  6  5  4  3  2  1];

significant_alphabet_bits = int32(12);
significant_factor = 2.^(significant_alphabet_bits-1)-1;
residue_factor = 2.*significant_factor;
codebook_alphabet = int32(0:13);

controlcode_prefixbits = 4;

for i=1:14
  residue_alphabet_prob = normpdf(-residue_factor:residue_factor,0,2.^-double(codebook_alphabet(i)).*double(residue_factor));
  residue_alphabet_freq = max(0.0000015625,residue_alphabet_prob./sum(residue_alphabet_prob));

  alphabet = num2cell(-residue_factor:residue_factor);
  frequencies = residue_alphabet_freq;

  [~, sidx] = sort(frequencies,'descend');
  alphabet_s = alphabet(sidx);
  frequencies_s = frequencies(sidx);

  tree = reserved_huffman(frequencies_s, alphabet_s, controlcode_prefixbits);
  [symbols, codes] = gencodebook(tree);

  controlid = find(strcmp(symbols,'control'));
  control_symbol = symbols(controlid);
  control_code = codes(controlid)
  
  symbols(controlid) = [];
  codes(controlid) = [];

  [~, sidx] = sort(cell2mat(symbols));
  symbols = symbols(sidx);
  codes = codes(sidx);
  schaeder_eff = (frequencies./sum(frequencies)) * cellfun(@numel,codes)
  plot(cell2mat(symbols),cellfun(@numel,codes)); hold on;
   
  %frequencies(floor(end/2)+[-1 0 1 2 3])
  %codes(floor(end/2)+[-1 0 1 2 3])
  %symbols(floor(end/2)+[-1 0 1 2 3])
  %max(cellfun(@numel,codes))
  %frequencies
  %codes
  %symbols


  tree = huffman(frequencies, alphabet);

  [symbols, codes] = gencodebook(tree);
  [~, sidx] = sort(cell2mat(symbols));
  symbols = symbols(sidx);
  codes = codes(sidx);

  huffman_eff = (frequencies./sum(frequencies)) * cellfun(@numel,codes)
  plot(cell2mat(symbols),cellfun(@numel,codes))
  hold off;
  drawnow;
  
  %frequencies(floor(end/2)+[-1 0 1 2 3])
  %codes(floor(end/2)+[-1 0 1 2 3])
  %symbols(floor(end/2)+[-1 0 1 2 3])
  %max(cellfun(@numel,codes))
  %frequencies
  %codes
  %symbols
end