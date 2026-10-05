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
    # overwrite it? By default only what an earlier import wrote — a row someone
    # corrected by hand is theirs now. `progress` hears the stats every `every`
    # entries. The collaborators are the models; a spec hands in its own.
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
      klass = @types.fetch(entry[:type])
      attrs = entry[:attrs].merge(brand: brand(entry[:brand], source: entry[:attrs][:source]))
      product = @products.shared.where(code: entry[:code]).first

      if product.nil?
        product = klass.new(attrs)
        outcome(product, entry, product.save ? :created : :invalid)
      elsif product.is_a?(klass) && @refresh.call(product)
        outcome(product, entry, product.update(attrs) ? :updated : :invalid)
      else
        outcome(product, entry, :kept)
      end
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
    end

    private

    def outcome(product, entry, result)
      stats[result] += 1
      if result == :invalid && @errors.size < 50
        @errors << "#{entry[:code]}: #{product.errors.full_messages.join(', ')}"
      end
    end
  end
end
