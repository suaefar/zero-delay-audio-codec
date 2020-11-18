# This file is part of the ZDAC reference implementation
# Author (2020) Marc René Schädler (suaefar@googlemail.com)

function out = limit(in,range)
  out = min(max(in,range(1)),range(2));
end
