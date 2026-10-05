require "json"
require "zlib"
require "openmarket/ean"

module Openmarket
  # One Open Food Facts row in, one catalogue entry out.
  #
  #   OpenFoodFacts.map(row)
  #   # => { code: "7891991010023", brand: "Brahma", type: "Drink", attrs: { ... } }
  #
  # Only drinks, and only drinks whose kind we can name — a row we cannot place
  # is skipped (nil), never guessed: a wrong row in an open database spreads.
  # Plain Ruby, no Mongoid: the importer decides what to do with an entry.
  #
  # Data: Open Food Facts, ODbL 1.0 — https://world.openfoodfacts.org
  module OpenFoodFacts
    DUMP_URL = "https://static.openfoodfacts.org/data/openfoodfacts-products.jsonl.gz"

    SOURCE = "off".freeze

    # A drink hangs under one of these.
    ROOTS = %w[ en:beverages en:alcoholic-beverages ].freeze

    # First rule with a tag on the row wins, so the narrow comes before the
    # wide: a gin is also a spirit, a cola is also a soda.
    KINDS = [
      [ :cachaca, %w[ en:cachacas ] ],
      [ :tequila, %w[ en:tequilas ] ],
      [ :vodka,   %w[ en:vodkas ] ],
      [ :gin,     %w[ en:gins ] ],
      [ :rum,     %w[ en:rums ] ],
      [ :whisky,  %w[ en:whiskies en:whiskeys en:bourbons en:scotch-whiskies ] ],
      [ :cognac,  %w[ en:cognacs en:brandies ] ],
      [ :cider,   %w[ en:ciders ] ],
      [ :wine,    %w[ en:wines ] ],
      [ :beer,    %w[ en:beers en:non-alcoholic-beers ] ],
      [ :liquor,  %w[ en:liqueurs en:spirits ] ],
      [ :energy,  %w[ en:energy-drinks ] ],
      [ :soda,    %w[ en:sodas en:carbonated-drinks en:colas ] ],
      [ :juice,   %w[ en:juices en:fruit-juices en:nectars en:juices-and-nectars ] ],
      [ :water,   %w[ en:waters en:mineral-waters en:spring-waters ] ]
    ].freeze

    # Nothing in them but water and sugar: no ABV on the label means 0, not
    # unknown. For the rest, no ABV means we do not know.
    SOFT = %i[ water soda juice energy ].freeze

    CANS    = %w[ en:can en:aluminium-can en:metal-can en:steel-can ].freeze
    GLASS   = %w[ en:glass en:glass-bottle ].freeze
    PLASTIC = %w[ en:plastic-bottle en:pet-bottle en:pet en:pet-1-polyethylene-terephthalate ].freeze
    BOTTLES = %w[ en:bottle ].freeze

    # ml per unit
    UNITS = {
      "ml" => 1, "cl" => 10, "dl" => 100,
      "l" => 1000, "lt" => 1000, "lts" => 1000,
      "litre" => 1000, "litres" => 1000, "liter" => 1000, "liters" => 1000,
      "litro" => 1000, "litros" => 1000,
      "oz" => 29.5735, "floz" => 29.5735
    }.freeze

    VOLUME   = /(\d+(?:[.,]\d+)?)\s*(ml|cl|dl|litres?|liters?|litros?|lts?|l|fl\.?\s*oz|oz)\b/i
    MULTIPACK = /(\d+)\s*[x×*]\s*#{VOLUME}/i
    MAX_ML   = 30_000

    module_function

    def map(row)
      code = Ean.normalize(row["code"]) or return
      tags = Array(row["categories_tags"])
      return unless tags.intersect?(ROOTS)

      kind = kind(tags) or return
      name = translations(row, "product_name")
      return if name.empty?

      info = translations(row, "generic_name")
      ml, count = volume(row["quantity"])
      ml ||= numeric(row["product_quantity"]) if row["product_quantity_unit"].to_s.downcase == "ml"

      attrs = {
        code: code,
        name_translations: name,
        kind: kind,
        pack: pack(row, name.values.join(" "), count),
        size: ml&.round&.then { |n| n if n.between?(1, MAX_ML) },
        acl: acl(row, kind),
        image: image(row),
        quantity: row["quantity"].to_s.strip.then { |q| q unless q.empty? },
        countries: slugs(row["countries_tags"]),
        tags: slugs(row["categories_tags"]),
        source: SOURCE
      }
      attrs[:info_translations] = info unless info.empty?

      { code: code, brand: brand(row), type: "Drink", attrs: attrs }
    end

    # The first brand on the label: "Brahma, Ambev" is a Brahma.
    def brand(row)
      row["brands"].to_s.split(",").map(&:strip).reject(&:empty?).first
    end

    def kind(tags)
      KINDS.find { |_, wanted| tags.intersect?(wanted) }&.first
    end

    # { "pt" => "Cerveja Brahma" } — the main name under the row's language,
    # plus any product_name_xx the contributors added.
    def translations(row, key)
      found = {}
      row.each do |name, value|
        next unless value.is_a?(String) && name =~ /\A#{key}_([a-z]{2,3})\z/
        found[$1] = value.strip unless value.strip.empty?
      end

      main = row[key].to_s.strip
      lang = (row["lang"] || row["lc"]).to_s
      lang = "en" unless lang.match?(/\A[a-z]{2,3}\z/)
      found[lang] ||= main unless main.empty?
      found
    end

    # [ml of one unit, units in the pack] from the label's own words:
    # "350 ml", "1,5 L", "33cl", "6 x 330 ml".
    def volume(quantity)
      text = quantity.to_s
      if (m = text.match(MULTIPACK))
        [ to_ml(m[2], m[3]), m[1].to_i ]
      elsif (m = text.match(VOLUME))
        [ to_ml(m[1], m[2]), 1 ]
      else
        [ nil, 1 ]
      end
    end

    def to_ml(amount, unit)
      factor = UNITS[unit.downcase.delete(" .")] or return
      amount.tr(",", ".").to_f * factor
    end

    def pack(row, name, count)
      return :kit if count > 1

      tags = Array(row["packaging_tags"])
      return :can if tags.intersect?(CANS)
      return :grf if tags.intersect?(GLASS)
      return :pet if tags.intersect?(PLASTIC)
      return :grf if tags.intersect?(BOTTLES)

      case name.to_s
      when /\b(lata|can)\b/i then :can
      when /\b(garrafa|long ?neck|bottle)\b/i then :grf
      when /\bpet\b/i then :pet
      end
    end

    # % by volume. Rows carry it as a nutriment; soft drinks without one are 0.
    def acl(row, kind)
      nutriments = row["nutriments"].is_a?(Hash) ? row["nutriments"] : {}
      value = %w[ alcohol_100g alcohol_value alcohol ].filter_map { |k| numeric(nutriments[k]) }.first
      value = 0.0 if value.nil? && SOFT.include?(kind)
      value&.round(2) if value&.between?(0, 100)
    end

    def image(row)
      url = row["image_front_url"] || row["image_url"]
      url.to_s if url.to_s.start_with?("http")
    end

    # "en:brazil" => "brazil"
    def slugs(tags)
      Array(tags).map { |tag| tag.to_s.sub(/\A[a-z]{2,3}:/, "") }.reject(&:empty?)
    end

    def numeric(value)
      Float(value.to_s.tr(",", "."))
    rescue ArgumentError
      nil
    end

    # Entries from a jsonl or jsonl.gz dump — a path or an open IO — one at a
    # time, so the whole of Open Food Facts never sits in memory. `countries`
    # keeps only rows sold there ("en:brazil"); `limit` stops after n entries.
    def each(source, countries: nil, limit: nil)
      return enum_for(:each, source, countries: countries, limit: limit) unless block_given?

      count = 0
      reading(source) do |io|
        io.each_line do |line|
          # Millions of rows are food. Skip them before paying for the parse.
          next unless line.include?("en:beverages") || line.include?("en:alcoholic-beverages")

          row = begin
            JSON.parse(line)
          rescue JSON::ParserError
            next
          end
          next if countries && !Array(row["countries_tags"]).intersect?(countries)

          entry = map(row) or next
          yield entry
          count += 1
          break if limit && count >= limit
        end
      end
    end

    def reading(source, &block)
      return yield(source) if source.respond_to?(:read)

      path = source.to_s
      if path.end_with?(".gz")
        Zlib::GzipReader.open(path, &block)
      else
        File.open(path, &block)
      end
    end
  end
end
