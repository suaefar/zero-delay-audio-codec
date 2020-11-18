# This file is part of the ZDAC reference implementation
# Author (2020) Marc René Schädler (suaefar@googlemail.com)

function tree = huffman(frequencies, alphabet)
  probabilities = frequencies./sum(frequencies);
  tree = num2cell(alphabet);
  while numel(tree) > 2
    [~, sidx] = sort(probabilities);
    probabilities(sidx(1)) = probabilities(sidx(1)) + probabilities(sidx(2));
    probabilities(sidx(2)) = [];
    tree{sidx(1)} = {tree{sidx(1)} tree{sidx(2)}};
    tree(sidx(2)) = [];
  end
end
