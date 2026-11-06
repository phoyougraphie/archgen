# frozen_string_literal: true

# Construit un RBZ reproductible : archgen.rb et archgen/ à la racine, sans tests
# ni documentation. ZIP écrit à la main avec zlib pour éviter toute dépendance.
require 'digest'
require 'zlib'
require 'fileutils'

module RbzPackager
  REPO = File.expand_path('..', __dir__)
  # Horodatage DOS figé (1980-01-01) : même contenu, même octets.
  DOS_TIME = 0
  DOS_DATE = 0x21

  module_function

  def entries
    files = Dir.glob('archgen/**/*', base: REPO).select { |f| File.file?(File.join(REPO, f)) }
    (['archgen.rb'] + files).uniq.sort
  end

  def deflate(data)
    z = Zlib::Deflate.new(Zlib::BEST_COMPRESSION, -Zlib::MAX_WBITS)
    z.deflate(data, Zlib::FINISH).tap { z.close }
  end

  def build(names = entries)
    body = String.new(encoding: 'BINARY')
    central = String.new(encoding: 'BINARY')
    names.each do |name|
      data = File.binread(File.join(REPO, name))
      packed = deflate(data)
      crc = Zlib.crc32(data)
      common = [20, 0x0800, 8, DOS_TIME, DOS_DATE, crc, packed.bytesize, data.bytesize, name.bytesize, 0].pack('vvvvvVVVvv')
      central << "PK\x01\x02".b << [20].pack('v') << common << [0, 0, 0, 0, body.bytesize].pack('vvvVV') << name.b
      body << "PK\x03\x04".b << common << name.b << packed
    end
    tail = "PK\x05\x06".b + [0, 0, names.size, names.size, central.bytesize, body.bytesize, 0].pack('vvvvVVv')
    body + central + tail
  end
end

if __FILE__ == $PROGRAM_NAME
  version = File.read(File.join(RbzPackager::REPO, 'archgen', 'version.rb'))[/VERSION = '([^']+)'/, 1]
  out = File.join(RbzPackager::REPO, 'pkg', "archgen-#{version}.rbz")
  FileUtils.mkdir_p(File.dirname(out))
  File.binwrite(out, RbzPackager.build)
  puts "Écrit #{out} (#{RbzPackager.entries.size} fichiers)"
  puts "SHA-256 #{Digest::SHA256.file(out).hexdigest}"
end
