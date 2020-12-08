function message = readbinary(filename_bin)
  fid = fopen(filename_bin,'r'); 
  if fid > 0
    num_data = fread(fid,inf,'uint8');
    fclose(fid);
    num_bytes = numel(num_data);
    num_bits = num_bytes.*8;
    message = zeros(1,num_bits,'logical');  
    decoder = (dec2bin(0:255) == '1').';
    bin_data = decoder(:,1+num_data);
    message = bin_data(:).';
  else
    message = logical([]);
  end
end


