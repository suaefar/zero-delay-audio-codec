function writebinary(filename_bin, message)
  num_bits = numel(message);
  num_bytes = ceil(num_bits./8);
  bin_data = zeros(8,num_bytes,'logical');
  bin_data(1:num_bits) = message;
  encoder = (2.^(7:-1:0));
  num_data = encoder * bin_data;
  fid = fopen(filename_bin,'w');  
  if fid > 0
    fwrite(fid, num_data, 'uint8');
    fclose(fid);
  endif
end

