# This file is part of the ZDAC reference implementation
# Author (2020) Marc René Schädler (suaefar@googlemail.com)

function out = predictor_lpc(in)
  persistent status;
  max_context = 32;
  max_coefficients = 3;

  if nargin() < 1
    status = [];
  else
    status = [status(max(1,end-max_context+2):end) double(in)];
    num_samples = numel(status);
    if num_samples > 3
      num_coefficients = min(max_coefficients,num_samples-2);
      [status_corr, corr_lag] = xcorr(status,num_coefficients);
      if any(status_corr ~= 0)
        a = levinson(status_corr(corr_lag>=0));   
        out = -(status(end-num_coefficients+1:end) * a(end:-1:2).').*((num_samples+1)./num_samples).^2;
      else
        out = 0;
      end
    else
      out = in;
    end
  end
end
