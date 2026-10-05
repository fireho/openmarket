# For the specs that need no Rails and no Mongo — the barcode, the Open Food
# Facts mapper, the dump format, the importer on fake models:
#
#   bin/rspec spec/lib
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "json"
require "stringio"
require "tmpdir"
require "zlib"

%w[ text ean open_food_facts dump download importer catalogue ].each { |file| require "openmarket/#{file}" }
