# This file is part of the ZDAC reference implementation
# Author (2020) Marc René Schädler (suaefar@googlemail.com)

function [signal_filtered, centers, filters, bandwidths] = mel_gammatone_iir(signal, fs, freq_range, supersample, qcontrol)

  % Activate cache
  persistent cache;
  
  % Single precision is sufficient
  if ~strcmp(class(signal),'single') || ~iscomplex(signal)
    signal = complex(single(signal));
  end
  
  % Frequency range to be considered
  if nargin < 3 || isempty(freq_range)
    freq_range = [64, 16000];
  end
  
  % Spectral supersampling factor
  if nargin < 4 || isempty(supersample)
    supersample = 2;
  end

  % Manipulation that trades spectral resolution vs. delay
  if nargin < 5 || isempty(qcontrol)
    qcontrol = 2;
  end
  
  % Keep it realistic
  freq_range(2) = min(floor(fs/2), freq_range(2));
  % Distance between center frequencies in Mel (taken from standard ASR)
  band_dist = (hz2mel(4000) - hz2mel(64))/(23+1); 
  % Resulting number of Mel-bands
  num_bands = floor((hz2mel(freq_range(2)) - hz2mel(freq_range(1)))/band_dist)-1;
  % Corresponding new upper frequency
  freq_range(2) = mel2hz(hz2mel(freq_range(1))+band_dist*(num_bands+1));
  % Determine frequencies equally-spaced in Mel
  freqs = mel2hz(linspace(hz2mel(freq_range(1)),hz2mel(freq_range(2)),(num_bands+2).*supersample));
  
  % Determine center frequencies and bandwidths
  centers = freqs(supersample+1:end-supersample);
  bandwidths = freqs(1+2.*supersample:end) - freqs(1:end-2.*supersample);

  % Build a config id string
  config = strrep(sprintf('c%.0f', fs, freq_range.*10, supersample, qcontrol.*1000),'-','_');
  
  if isempty(cache) || ~isfield(cache, config)
    impulse = complex(single([zeros(4,1); 1; zeros(fs-5,1)]));
    filters = complex(single(zeros(length(centers),2)));
    fir_approxs = complex(single(zeros(fs,length(centers))));
    for i=length(centers):-1:1
      % Load definition
      center = centers(i);
      bandwidth = bandwidths(i);

      % Determine L
      L = qcontrol./sqrt(2) .* 10000./bandwidth + 0.5;

      % Construct filter
      p = (1-1./L).*exp(1i.*2.*pi.*center./fs);
      b0 = complex(single(1i));
      a1 = complex(single(p));

      % Measure impulse response
      fir_approx = iir4(b0, a1, impulse);
      
      % Find best phase relative to preceeding filter
      if i < length(centers)
        reference = fir_approxs(:,i+1);
        [~, referencesample] = max(abs(fir_approx).*abs(reference));
        referencephase = angle(reference(referencesample));
        b0 = b0 .* exp(1i.*(referencephase-angle(fir_approx(referencesample))));
      end

      % Normalize gain (calibration of filterbank)
      b0 = b0 .* (2 ./ max(abs(fft(fir_approx))));
      
      % Re-measure impulse response
      fir_approx = iir4(b0, a1, impulse);

      % Save 
      fir_approxs(:,i) = fir_approx;
      filters(i,:) = [b0 a1];
    end
    % Save filters for later use
    cache.(config).filters = filters;
    cache.(config).centers = centers;
  else
    % Load filters from cache
    filters = cache.(config).filters;
    centers = cache.(config).centers;
  end
  
  % Perform filtering
  signal_filtered = iir4(filters(:,1), filters(:,2), signal);

end

function f = mel2hz (m)
  % Converts frequency from Mel to Hz
  f = 700.*((10.^(m./2595))-1);
end

function m = hz2mel (f)
  % Converts frequency from Hz to Mel
  m = 2595.*log10(1+f./700);
end
