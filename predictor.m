# This file is part of the ZDAC reference implementation
# Author (2020) Marc René Schädler (suaefar@googlemail.com)

function out = predictor(in)
  max_coefficients = 4;
  num_samples = numel(in);
  if num_samples < 4
    out = in(end);
  else
    num_coefficients = min(max_coefficients,num_samples-2);
    in_padd = [in; zeros(num_coefficients,1)];
    in_acorr = sum(in .* in_padd((0:num_coefficients) + (1:num_samples).'));
    %[in_acorr, corr_lag] = xcorr(in,num_coefficients);
    % in_acorr = in_corr(corr_lag>=0)
    if any(in_acorr ~= 0)
      a = levinson(in_acorr);
      out = -(in(end-num_coefficients+1:end).' * a(end:-1:2).').*((num_samples+1)./num_samples).^2;
    else
      out = 0;
    end
  end
end

