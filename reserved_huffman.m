function tree = reserved_huffman(frequencies, alphabet, depth)
  
  if numel(frequencies) == 1
    tree = alphabet{1};
  else
    if depth > 0
      cfrequencies = cumsum(frequencies);
      cfrequencies = cfrequencies./cfrequencies(end);
      num_0 = sum(cfrequencies<0.5);
      num_0 = max(1,num_0);
      num_0 = min(numel(frequencies)-1,num_0);      
      tree_0 = huffman(frequencies(1:num_0), alphabet(1:num_0));
      tree_1 = reserved_huffman(frequencies(num_0+1:end), alphabet(num_0+1:end), depth - 1);
      tree = {tree_0 tree_1};
    elseif depth > -1
      tree_0 = 'control';
      tree_1 = reserved_huffman(frequencies, alphabet, depth - 1);
      tree = {tree_0 tree_1};
    else
      tree = huffman(frequencies, alphabet);
    end
  end
end
