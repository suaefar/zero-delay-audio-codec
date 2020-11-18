# This file is part of the ZDAC reference implementation
# Author (2020) Marc René Schädler (suaefar@googlemail.com)

function [symbols, codes] = gencodebook(tree)
  if ~iscell(tree)
    symbols = { tree };
    codes = { [] };
  else
    [symbols0, codes0] = gencodebook(tree{1});
    [symbols1, codes1] = gencodebook(tree{2});
    for i=1:length(symbols0)
      codes0{i} = logical([0 codes0{i}]);
    end
    for i=1:length(symbols1)
      codes1{i} = logical([1 codes1{i}]);
    end
    symbols = [symbols0(:); symbols1(:)];
    codes = [codes0(:); codes1(:)];
  end
end
