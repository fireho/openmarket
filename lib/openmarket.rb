require "openmarket/version"
require "openmarket/text"
require "openmarket/ean"
require "openmarket/open_food_facts"
require "openmarket/line"
require "openmarket/dump"
require "openmarket/download"
require "openmarket/wikidata"
require "openmarket/importer"
require "openmarket/catalogue"
require "openmarket/builder"
require "openmarket/railtie"
require "openmarket/engine"

module Openmarket
  # The open catalogue as of the gem's last data commit: what `rake
  # openmarket:restore` loads when the latest release cannot be downloaded.
  SNAPSHOT = File.expand_path("../db/openmarket.ndjson.gz", __dir__)
end
