# This file is part of the ZDAC reference implementation
# Author (2020) Marc René Schädler (suaefar@googlemail.com)

function tree = huffman(frequencies, alphabet)
  assert(numel(frequencies)==numel(frequencies));
  if numel(frequencies) == 1
    tree = alphabet{1};
  else
    probabilities = frequencies./sum(frequencies);
    tree = alphabet;
    while numel(tree) > 2
      [~, sidx] = sort(probabilities);
      probabilities(sidx(1)) = probabilities(sidx(1)) + probabilities(sidx(2));
      probabilities(sidx(2)) = [];
      tree{sidx(1)} = {tree{sidx(1)} tree{sidx(2)}};
      tree(sidx(2)) = [];
    end
  end  
end
