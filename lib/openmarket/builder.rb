require "json"
require "openmarket/catalogue"
require "openmarket/dump"
require "openmarket/ean"
require "openmarket/open_food_facts"
require "openmarket/text"

module Openmarket
  # The published dump, made straight from Open Food Facts entries — no Mongo,
  # no Rails — so a GitHub Action can rebuild it every month:
  #
  #   builder = Openmarket::Builder.new
  #   Openmarket::OpenFoodFacts.each("off.jsonl.gz") { |entry| builder.add(entry) }
  #   builder.write("openmarket.ndjson.gz")
  #
  # Its records are the ones Catalogue.dump writes from a database, so
  # `openmarket:restore` cannot tell them apart. The whole catalogue sits in
  # memory as plain hashes; the world's drinks (some 300k) fit.
  class Builder
    # What a Wikidata record may say about a brand. Never its name: a brand is
    # called what its products call it.
    ENRICHED = %w[ info wikidata country site logo source ].freeze

    # `brands` are Wikidata brand records, shaped like the dump's
    # ({ "type" => "brand", "name" => "Brahma", "wikidata" => "Q...", ... }).
    def initialize(brands: [])
      @products = {} # code => its record, the brand as that row spelled it
      @keys = {}     # a brand's spelling => its folded name
      @wikidata = {} # a folded name => what Wikidata says about it
      @stats = { read: 0, duplicates: 0, invalid: 0 }
      enrich(brands)
    end

    # One entry from OpenFoodFacts.map. Two rows can be one product — a UPC-E
    # and its UPC-A, a code entered twice — and the one that says more is kept,
    # whichever came first. Returns :added, :duplicate or :invalid.
    def add(entry)
      @stats[:read] += 1
      code = Ean.normalize(entry[:code]) || entry[:code].to_s.strip
      if code.empty?
        @stats[:invalid] += 1
        return :invalid
      end

      record = product_record(entry, code)
      kept = @products[code]
      @products[code] = kept ? richer(kept, record) : record
      return :added unless kept

      @stats[:duplicates] += 1
      :duplicate
    end

    # Wikidata records join the brands by folded name, so "ANTARTICA" on a can
    # meets "Antártica" on Wikidata; the first record for a name wins. All or
    # nothing: a fetch that breaks halfway leaves the brands as they were.
    def enrich(brands)
      found = {}
      brands.each do |record|
        folded = key(record["name"])
        found[folded] ||= Dump.slim(record.slice(*ENRICHED)) unless folded.empty?
      end
      @wikidata = found.merge(@wikidata)
      self
    end

    # The brands the products use, as the dump names them: what to ask Wikidata.
    def brand_names = names.values.sort

    # Brands (only those a product uses) by name, then products by code: the
    # order Catalogue.records gives, so two builds diff cleanly.
    def records
      Enumerator.new do |out|
        names = self.names
        names.sort_by { |_, name| name }.each { |key, name| out << brand_record(name, @wikidata[key]) }
        @products.keys.sort.each do |code|
          record = @products[code]
          out << (record["brand"] ? record.merge("brand" => names[key(record["brand"])]) : record)
        end
      end
    end

    # Writes the dump; returns how many records.
    def write(path) = Dump.write(path, records)

    # What came in (read, duplicates, invalid) and what goes out (products,
    # brands, and how many of those Wikidata knows).
    def stats
      names = self.names
      @stats.merge(products: @products.size, brands: names.size, wikidata: names.count { |key, _| @wikidata.key?(key) })
    end

    private

    # folded name => the spelling most of its products use: "Brahma" when more
    # rows say it than "BRAHMA", the alphabetically first on a tie — so the same
    # rows always give the same name.
    def names
      counts = Hash.new { |hash, key| hash[key] = Hash.new(0) }
      @products.each_value { |record| counts[key(record["brand"])][record["brand"]] += 1 if record["brand"] }
      counts.transform_values { |spellings| spellings.min_by { |name, n| [ -n, name ] }.first }
    end

    # Catalogue.product_record, from an entry instead of a document. Tags,
    # countries and brands repeat across thousands of rows, so each is kept once.
    def product_record(entry, code)
      attrs = entry[:attrs]
      brand = entry[:brand].to_s.strip
      record = {
        "type" => Catalogue::TYPES.key(entry[:type]) || "product",
        "code" => code, "name" => attrs[:name_translations], "info" => attrs[:info_translations],
        "brand" => (-brand unless key(brand).empty?), "image" => attrs[:image], "quantity" => attrs[:quantity],
        "countries" => attrs[:countries]&.map(&:-@), "tags" => attrs[:tags]&.map(&:-@), "source" => attrs[:source]
      }
      case record["type"]
      when "drink" then record.merge!("kind" => attrs[:kind]&.to_s, "pack" => attrs[:pack]&.to_s, "size" => attrs[:size], "acl" => attrs[:acl])
      when "food" then record.merge!("kind" => attrs[:kind]&.to_s, "size" => attrs[:size])
      end
      Dump.slim(record)
    end

    # Catalogue.brand_record. A brand comes from the products' rows (Open Food
    # Facts) until Wikidata says something about it.
    def brand_record(name, wikidata)
      record = {
        "type" => "brand", "name" => name, "info" => nil, "wikidata" => nil,
        "country" => nil, "site" => nil, "logo" => nil, "source" => OpenFoodFacts::SOURCE
      }
      Dump.slim(record.merge(wikidata || {}))
    end

    # The record that says more: more fields, then more names, then more tags.
    # Its JSON settles a tie, so the winner never depends on the order of rows.
    def richer(*twins)
      twins.max_by { |record| [ record.size, record["name"].to_h.size, record["tags"].to_a.size, JSON.generate(record) ] }
    end

    def key(spelling) = (@keys[spelling] ||= Text.fold(spelling))
  end
end
