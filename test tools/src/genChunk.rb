require 'digest'
require 'fileutils'
require 'zlib'

def b_hashes_file( dd_path )
  b_hashes = []
  File.open( dd_path ) do |f|
    while !f.eof? do
      b_hashes.push( Digest::SHA1.digest( f.read(4096) ) )
    end
  end
  b_hashes
end

def md5sum_file( dd_path )
  b_hashes = b_hashes_file( dd_path )
  Digest::MD5.hexdigest( b_hashes.join )
end

def b_hashes_data( buf )
  b_hashes = []
  size = 0
  while size < buf.size do
    b_hashes.push( Digest::SHA1.digest( buf[size, 4096] ) )
    size += 4096
  end
  b_hashes
end

def md5sum_data( buf )
  b_hashes = b_hashes_data( buf )
  Digest::MD5.hexdigest( b_hashes.join )
end

def crc32_file( dd_path )
  cksum = 0
  File.open( dd_path ) do |f|
    while !f.eof? do 
      cksum = Zlib::crc32( f.read(4096000), cksum )
    end
  end
  cksum.to_s(16)
end

def crc32_file_0filled( dd_path )
  cksum = 0
  File.open( dd_path ) do |f|
#    File.open( dd_path + ".padded", "w+") do |g|
      while !f.eof? do 
        data = f.read(4096)
        if data.size < 4096
          padLen = 4096 - data.size
          data += Array.new(padLen, 0).pack("C*")
#          data = data.ljust(4096, '\x00')
        end
        chunksum = Zlib::crc32( data, 0 )
        oldCksum = cksum
        cksum = Zlib::crc32( data, cksum )
        puts "cksum:(%08x)%08x->%08x" % [chunksum, oldCksum, cksum]
#        puts "cksum:#{oldCksum.to_s(16)}->#{cksum.to_s(16)}"
#        g.write(data)
      end
#    end
  end
  "%08x" % cksum
end

nBlocks = 1

buf = "0"*4096

$chars = ("a".."z").to_a + ("A".."Z").to_a + ("0".."9").to_a + 
  ["~", "!", "@", "#", "$", "%", "^", "&", "*", "(",
   ")", "-", "=", "_", "+", ",", ".", "/", "<", ">", 
   "?", ";", ":", "[", "]", "{", "}", "|", "`", "'"]

def genBlocks(suffix = "000", nBlks = 1, maxCount = 0, startCi = 0)
  basedir = $installDir || "../raw"
  dir = basedir + "/pt#{suffix}/b#{nBlks}k#{startCi}"
  return dir if
    File.exist?( dir ) && Dir.entries( dir ).size >= maxCount + 2
  print "genBLocks(#{suffix}, #{nBlks}, #{maxCount})"
  count = 0
  suffixLen = suffix.size
  $chars.each_index do |ci|
    next if startCi > 0 && ci < startCi
    base_c = $chars[ci]
    buf = ((base_c *63 + "\n")*64) * nBlks # 4k block
    bufSize = buf.size
    0.upto(bufSize - 1) do |idx| 
      old_c = buf[idx]
      $chars.each do |x|
        buf[idx] = x
        chunkSig = md5sum_data( buf )
#        blockSig = Digest::SHA1.digest(buf)
#        chunkSig = Digest::MD5.hexdigest(blockSig)
        next unless (chunkSig[-suffixLen, suffixLen] == suffix) 
#        next unless (chunkSig[-3,3] == "000") 
        dir = basedir + "/pt#{suffix}/b#{nBlks}k#{ci}"
        unless File.exists?( dir )
          FileUtils.mkdir_p(dir)
        end
        name = dir + "/#{chunkSig}"
        unless File.exist?( name ) && File.size( name ) == buf.size
          File.open(name, "w") do |f|
            f.write(buf)
          end
        end
        print "."
        count += 1
        break if (maxCount > 0 && count >= maxCount)
      end
      buf[idx] = old_c
      break if (maxCount > 0 && count >= maxCount)
    end
    break if (maxCount > 0 && count >= maxCount)
  end
  puts "dir:#{dir}; cnt:#{count}"
  dir
end

# genBlocks("a17", 256, 20)
# genBlocks("a17", 50, 20)

def genBZ
  genBlocks("a17", 3, 100)
  genBlocks("a17", 4, 100)
  genBlocks("a17", 5, 100)
end

def genBZtf1
  FileUtils.mkdir_p("../raw") unless File.exist?("../raw")
  File.open("../raw/tf1", "w+") do |f|
    f.write(IO.read("../pta17/b3k0/0c5691a21280fcf0aa21b4a3ccc8ca17"))
    f.seek(4096, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b4k0/fe425621be7db594404e53c28b87ba17"))
    f.seek(4096*5, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b5k0/7b22af8aa42303091d6606a73dc07a17"))
  end
end

def genBZtf2
  File.open("../raw/tf2", "w+") do |f|
    f.seek(4096*2, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b3k0/b01a5423a9a404629436d1b91cce2a17"))
    f.seek(4096*5, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b4k0/c860703f949e6a3cc65961957d7b1a17"))
    f.seek(4096*3, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b5k0/2327f311de3301a4a9bfa6fb922eaa17"))
  end
end

def genBZtf3
  File.open("../raw/tf3", "w+") do |f|
    f.write(IO.read("../pta17/b3k0/38dd710e565f9ff3b5551ebdae2f1a17"))
    f.seek(4096*2, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b3k0/b4d9e4e2488ae460ec07f8a9f472ca17"))
    f.seek(4096*3, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b4k0/448de9984c37276936ef63b3cba15a17"))
    f.seek(4096*4, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b5k0/0f99921f804346214b81e1fb64aa1a17"))
  end
end  
  
def genBZtf4
  File.open("../raw/tf4", "w+") do |f|
    f.write(IO.read("../pta17/b3k0/3e95ade8993f9b35f84eb55412287a17"))
    f.seek(4096*2, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b3k0/b01a5423a9a404629436d1b91cce2a17"))
    f.seek(4096*3, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b4k0/448de9984c37276936ef63b3cba15a17"))
    f.seek(4096*2, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b5k0/225e4c2f57ff3c7db973a678a92c1a17"))
  end
end  

def genBZtf5
  File.open("../raw/tf5", "w+") do |f|
    f.write(IO.read("../pta17/b256k0/7304b08a744631c3853a96ada99d7a17"))
    f.write(IO.read("../pta17/b256k0/2ed9bf25da39c5779a210bb57893ca17"))
    f.write(IO.read("../pta17/b256k0/2fcd3d65df88c376ebc0ac5995719a17"))
    f.write(IO.read("../pta17/b256k0/08c987cdcec1b4ca4d69a919be2bea17"))
    f.write(IO.read("../pta17/b256k0/fc45c3f51889d165e3ec63b33b17fa17"))

    f.write(IO.read("../pta17/b256k0/f3b229bc68f84eb8f367ad6dca316a17"))
    f.write(IO.read("../pta17/b256k0/962137498b45b2d26fddd47396bf6a17"))
    f.write(IO.read("../pta17/b256k0/8de98303053ae030679f9574149cba17"))
    f.write(IO.read("../pta17/b256k0/64a1ceb94affe796c22d3556ea5f0a17"))
    f.write(IO.read("../pta17/b256k0/3a94ff827a186361a5e34305bf593a17"))

    f.write(IO.read("../pta17/b256k0/26da00ca31afbd065e636af397a9ba17"))
    f.write(IO.read("../pta17/b256k0/25eb8ebce41142be5b09b0323efd5a17"))
    f.write(IO.read("../pta17/b256k0/f3b229bc68f84eb8f367ad6dca316a17"))
    f.write(IO.read("../pta17/b256k0/ec58d4e2fc83cb4fa5806fb24c8eea17"))
    f.write(IO.read("../pta17/b256k0/c441215fbb1a0494d7193282e8461a17"))

    f.write(IO.read("../pta17/b256k0/d7324be39641f96a653f5dab324fca17"))
    f.write(IO.read("../pta17/b256k0/4094df301592965e55af9c8507527a17"))
    f.write(IO.read("../pta17/b256k0/1ca23b6085d7c49e2ce43485c4337a17"))
    f.write(IO.read("../pta17/b256k0/2b6931b18e26e9d9c743a4b814c19a17"))
    f.write(IO.read("../pta17/b256k0/8a76eccab5856055cf7bb9eb3f760a17"))

    f.write(IO.read("../pta17/b256k0/e5b9c10409e2b435837f07338d6caa17"))
    f.write(IO.read("../pta17/b256k0/08c987cdcec1b4ca4d69a919be2bea17"))
    f.write(IO.read("../pta17/b256k0/2fcd3d65df88c376ebc0ac5995719a17"))
    f.write(IO.read("../pta17/b256k0/25eb8ebce41142be5b09b0323efd5a17"))
    f.write(IO.read("../pta17/b256k0/25eb8ebce41142be5b09b0323efd5a17"))

    f.write(IO.read("../pta17/b256k0/fc45c3f51889d165e3ec63b33b17fa17"))
    f.write(IO.read("../pta17/b256k0/3a94ff827a186361a5e34305bf593a17"))
  end
end

def genBZtf6
  File.open("../raw/tf6", "w+") do |f|
    f.write(IO.read("../pta17/b50k0/08ba0aa2d2b1c6ef896780d1c470aa17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b50k0/0e4072db1d517dbeea8c59acf2419a17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b50k0/2e63bc9b99ba976793d1e033972eba17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b50k0/2f31d665039e6e5d28e6034f23b36a17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b50k0/2f74a93a3fed35de7f8c05edbdbe7a17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b50k0/4787fd3ee6c522efaf1921fc8514ea17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b50k0/5bd8ff3edf0c9663c916f6c72decfa17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b50k0/5cd11f9827d7aca00f7aa11d6fac3a17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b50k0/67c027ff1b60fef0377d7278968dba17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b50k0/6c98dcc5847453d24821ed079e200a17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b50k0/790c6b84a6ee3bfb94a38d15bf914a17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b50k0/851109eece24d0393fd88e98cab48a17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b50k0/8ed6ee91702c77fb7f8e8a3ca53c7a17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b50k0/b46cad965ea5e943800a9ba9b34d9a17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b50k0/b6198dbd158974f515e9061257797a17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b50k0/c2dd93dbf991323611f9ec815c1b2a17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b50k0/c6f06bb9b1deddfbd28a83a8f3aa1a17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b50k0/dfbe2d10c017438623203a24fef8ba17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b50k0/eb6e120ddbdaaa5eddc79699933c5a17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b50k0/f3d2dbd0d3fe5733921a11e0c5654a17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b120k0/06bcca1f6a9c97484bb93a3d6b109a17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b120k0/11667eb599ef072570abcbfc25892a17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b120k0/1943aa37f174f990e18e07b434a87a17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b120k0/38a100d0acb83a9616a65b3278db3a17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b120k0/3b785d8c5b5cb8b03bcce2b642deba17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b120k0/532fef8bc3b16f80ad335cab2ad89a17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b120k0/650140024aaa616295c72380ba4f1a17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b120k0/7ba8cd740f473b23c072ce269eec4a17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b120k0/90d1e2beac7d1e8349f81f0799625a17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b120k0/97f70195e620364e58b410f65bba8a17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b120k0/9ef15f940eac1f8db00be0e5e40eaa17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b120k0/a834827e32c560966f302d482e495a17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b120k0/ae1eb61ebbf6e831a03c221710a0ba17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b120k0/cf270bc05191ba78f9560c5d092cea17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b120k0/da370f102d0dd82b7d01993644403a17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b120k0/da62d99fa17b3776979f4c12fc0c3a17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b120k0/dad45991d39d55bf7328d87d913efa17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b120k0/e4cf3210bf6fa98384364b1ac0a77a17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b120k0/efae00345ddd27fd395fb8d15485ea17"))
    f.seek(4096*20, IO::SEEK_CUR)
    f.write(IO.read("../pta17/b120k0/f7fe37918e6919a95f1428cf7beafa17"))
  end
end

=begin

0.upto(4095) do |idx|
  genChunk(idx)
end

def genChunk2(idx0, idx1)
  buf = "0"*4096
  $chars.each do |x|
    $chars.each do |y|
      buf[idx0] = x
      buf[idx1] = y
      blockSig = Digest::SHA1.digest(buf)
      chunkSig = Digest::MD5.hexdigest(blockSig)
#    puts "sig:#{chunkSig}"
      next unless (chunkSig[-3,3] == "000") 
      name = "../bk2/#{chunkSig}"
      File.open("../bk2/#{chunkSig}", "w") do |f|
        f.write(buf)
      end
    end
  end
end

0.upto(4094) do |x|
  (x+1).upto(4095) do |y|
    genChunk2(x, y)
  end
end


("a".."z").each do |x|
  File.open("../raw/block-#{x}.dat", "w") do |f|
    f.write(x*4096)
  end
end

File.open("../raw/Block-a_b_c.dat", "w+") do |f|
  f.write("a"*4096)
  f.seek(4096, IO::SEEK_CUR)
  f.write("b"*4096)
  f.seek(4096, IO::SEEK_CUR)
  f.write("c"*4096)
end

=end

