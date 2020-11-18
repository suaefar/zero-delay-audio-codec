# This file is part of the ZDAC reference implementation
# Author (2020) Marc René Schädler (suaefar@googlemail.com)

function out = predictor_linear(in)
  persistent status;
  if nargin() < 1
    status = [];
  else
    if isempty(status)
      status = [in in];
    else
      status = [status(end) in];
    end
    out = status(2) + (status(2) - status(1));
  end
end
