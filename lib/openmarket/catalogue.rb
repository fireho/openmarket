require "openmarket/dump"
require "openmarket/importer"

module Openmarket
  # The shared catalogue to a dump file and back. Only the shared rows travel:
  # an org's own products (a house recipe) are never in a dump, and a product
  # with no code has nothing to be known by on the other side, so it stays too.
  module Catalogue
    TYPES = { "drink" => "Drink", "food" => "Food" }.freeze

    module_function

    # Writes the catalogue to `path` (.ndjson or .ndjson.gz); returns the count.
    def dump(path)
      Dump.write(path, records)
    end

    # Loads a dump. What is already there is left alone unless `overwrite`;
    # returns the importer's stats.
    def restore(path, overwrite: false, **options)
      importer = Importer.new(refresh: ->(_product) { overwrite }, **options)
      Dump.read(path) do |record|
        if record["type"] == "brand"
          importer.brand(record["name"], update: overwrite, **brand_attrs(record))
        else
          importer.import(entry(record))
        end
      end
      importer.stats
    end

    # Brands, then products — brands first so a product's brand is already there.
    def records
      Enumerator.new do |out|
        products = ::Product.shared.where(code: { "$nin" => [ nil, "" ] })
        ids = products.distinct(:brand_id).compact
        brands = ::Brand.where(_id: { "$in" => ids }).order_by(name: 1).to_a

        brands.each { |brand| out << brand_record(brand) }
        names = brands.to_h { |brand| [ brand.id, brand.name ] }
        products.order_by(code: 1).each { |product| out << product_record(product, names) }
      end
    end

    def brand_record(brand)
      {
        "type" => "brand", "name" => brand.name, "info" => brand.info, "wikidata" => brand.wikidata,
        "country" => brand.country, "site" => brand.site, "logo" => brand.logo, "source" => brand.source
      }
    end

    # `brands` maps a brand id to its name — the dump says "Brahma", not an id.
    def product_record(product, brands = {})
      record = {
        "type" => product.drink? ? "drink" : (product.food? ? "food" : "product"),
        "code" => product.code, "name" => product.name_translations, "info" => product.info_translations,
        "brand" => brands[product.brand_id], "image" => product.image, "quantity" => product.quantity,
        "countries" => product.countries, "tags" => product.tags, "source" => product.source
      }
      if product.drink?
        record.merge!("kind" => product.kind&.to_s, "pack" => product.pack&.to_s, "size" => product.size, "acl" => product.acl)
      elsif product.food?
        record.merge!("kind" => product.kind&.to_s, "size" => product.size)
      end
      record
    end

    def brand_attrs(record)
      %w[ info wikidata country site logo source ].to_h { |key| [ key.to_sym, text(record[key]) ] }
    end

    # A dump record as an importer entry. Only known fields cross over, and only
    # in their own shape: a dump from the internet does not get to set whatever
    # it likes on a document, and a wrong value makes a row invalid, not a crash.
    def entry(record)
      type = TYPES.fetch(record["type"], "Product")
      attrs = {
        code: text(record["code"]), name_translations: translations(record["name"]),
        info_translations: translations(record["info"]), image: text(record["image"]),
        quantity: text(record["quantity"]), source: text(record["source"]),
        countries: texts(record["countries"]), tags: texts(record["tags"])
      }
      if type == "Drink"
        attrs.merge!(kind: text(record["kind"]), pack: text(record["pack"]), size: count(record["size"]), acl: amount(record["acl"]))
      elsif type == "Food"
        attrs.merge!(kind: text(record["kind"]), size: count(record["size"]))
      end

      { code: text(record["code"]), brand: text(record["brand"]), type: type, attrs: attrs }
    end

    def text(value) = (value if value.is_a?(String) && !value.strip.empty?)
    def texts(value) = value.is_a?(Array) ? value.select { |item| text(item) } : []
    def count(value) = (value if value.is_a?(Integer))
    def amount(value) = (value.to_f if value.is_a?(Numeric) && value.to_f.finite?)

    # { "pt" => "Cerveja" } — anything else is no name at all.
    def translations(value)
      return unless value.is_a?(Hash)

      found = value.select { |locale, name| locale.is_a?(String) && text(name) }
      found unless found.empty?
    end
  end
end
