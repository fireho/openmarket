require "openmarket/ean"
require "openmarket/text"

module Openmarket
  # Entries in, shared catalogue rows out. An entry is what an importer made of
  # one source row — OpenFoodFacts.map, or a dump record through Catalogue.entry:
  #
  #   { code: "7891991010023", brand: "Brahma", type: "Drink", attrs: { name_translations: ... } }
  #
  # Every row is shared (no org): an import fills the catalogue everybody picks
  # from. One bad row is counted and set aside, never allowed to stop the rest.
  #
  #   importer = Openmarket::Importer.new
  #   importer.call(Openmarket::OpenFoodFacts.each("off.jsonl.gz", countries: %w[ en:brazil ]))
  #   importer.stats   # => { created: 812, updated: 40, kept: 3, invalid: 1 }
  class Importer
    attr_reader :stats, :errors

    # `refresh` is asked about a product that is already there: may this import
    # overwrite it? By default only what an earlier import wrote and nobody has
    # edited since (an edit clears `source`). `progress` hears the stats every
    # `every` entries. The collaborators are the models; a spec hands in its own.
    def initialize(refresh: ->(product) { product.source == "off" }, progress: nil, every: 1000,
                   brands: ::Brand, products: ::Product, types: nil)
      @refresh, @progress, @every = refresh, progress, every
      @brands, @products = brands, products
      @types = types || { "Drink" => ::Drink, "Food" => ::Food, "Product" => ::Product }
      @stats = Hash.new(0)
      @errors = []
      @cache = {}
      @seen = 0
    end

    def call(entries)
      entries.each { |entry| import(entry) }
      stats
    end

    def import(entry)
      code = Ean.normalize(entry[:code]) || entry[:code].to_s.strip
      return outcome(:invalid, entry, "no code") if code.empty?

      klass = @types.fetch(entry[:type]) { return outcome(:invalid, entry, "unknown type #{entry[:type].inspect}") }
      attrs = entry[:attrs].merge(code: code, brand: brand(entry[:brand], source: entry[:attrs][:source]))
      # Found by any spelling, as a scan finds it: a row typed as a UPC-A is
      # the same product as the EAN-13 this import brings.
      spellings = Ean.variants(code).then { |found| found.empty? ? [ code ] : found }
      product = @products.shared.where(code: { "$in" => spellings }).first

      if product.nil?
        product = klass.new(attrs)
        saved(product, entry, :created)
      elsif product.is_a?(klass) && @refresh.call(product)
        product.assign_attributes(attrs)
        saved(product, entry, :updated)
      else
        outcome(:kept, entry)
      end
    rescue StandardError => e
      outcome(:invalid, entry, "#{e.class}: #{e.message}")
    ensure
      @seen += 1
      @progress&.call(stats) if (@seen % @every).zero?
    end

    # The brand a name means — found however it was cased or accented, made
    # when it is new. nil for no name, and for a name that will not save.
    # The keywords are what a new brand starts with; `update` also rewrites a
    # brand that is already there.
    def brand(name, update: false, **attrs)
      key = Text.fold(name)
      return if key.empty?
      return @cache[key] if @cache.key?(key) && !update

      found = @brands.named(name)
      if found
        found.update(attrs) if update && !attrs.empty?
      else
        found = @brands.new(attrs.merge(name: name.to_s.strip))
        unless found.save
          stats[:brand_invalid] += 1
          found = nil
        end
      end
      @cache[key] = found
    rescue StandardError => e
      stats[:brand_invalid] += 1
      remember("brand #{name.inspect}: #{e.class}: #{e.message}")
      nil
    end

    private

    def saved(product, entry, result)
      product.importing = true if product.respond_to?(:importing=)
      product.save ? outcome(result, entry) : outcome(:invalid, entry, product.errors.full_messages.join(", "))
    end

    def outcome(result, entry, why = nil)
      stats[result] += 1
      remember("#{entry[:code]}: #{why}") if why
      result
    end

    def remember(error)
      @errors << error if @errors.size < 50
    end
  end
end
