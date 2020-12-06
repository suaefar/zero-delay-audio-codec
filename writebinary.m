function writebinary(filename_bin, message)
  num_bits = numel(message);
  num_bytes = ceil(num_bits./8);
  
  fid = fopen(filename_bin,'w');
  decode_bits = 2.^(7:-1:0);
  if fid > 0
    for i=1:num_bytes
      message_bits = message(min(end,(i-1)*8+1:i*8));
      byte_data = uint8(sum(message_bits.*decode_bits(1:numel(message_bits)),'native'));
      fwrite(fid, byte_data);
    end
    fclose(fid);
  endif
end

