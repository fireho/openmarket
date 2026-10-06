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
  # The tags below are ids from the OFF taxonomies (taxonomies/food/categories.txt,
  # packaging_shapes.txt, packaging_materials.txt in openfoodfacts-server). A
  # row's categories_tags carries every ancestor of its categories.
  #
  # Data: Open Food Facts, ODbL 1.0 — https://world.openfoodfacts.org
  module OpenFoodFacts
    DUMP_URL = "https://static.openfoodfacts.org/data/openfoodfacts-products.jsonl.gz"
    IMAGES = "https://images.openfoodfacts.org/images/products"

    SOURCE = "off".freeze

    # A drink hangs under one of these.
    ROOTS = %w[ en:beverages en:alcoholic-beverages ].freeze
    ALCOHOLIC = "en:alcoholic-beverages".freeze
    NON_ALCOHOLIC = "en:non-alcoholic-beverages".freeze

    # First rule with a tag on the row wins, so the narrow comes before the
    # wide: a gin is also a hard liquor, a sparkling water is also a carbonated
    # drink, a ginger beer sits under the non-alcoholic beers.
    KINDS = [
      [ :cachaca, %w[ en:cachaca ] ],
      [ :tequila, %w[ en:tequilas en:mezcal ] ],
      [ :vodka,   %w[ en:vodka ] ],
      [ :gin,     %w[ en:gins ] ],
      [ :rum,     %w[ en:rums ] ],
      [ :whisky,  %w[ en:whisky ] ],
      [ :cognac,  %w[ en:cognac en:brandys ] ],
      [ :mixed,   %w[ en:premixed-alcoholic-beverages en:hard-seltzers ] ],
      [ :cider,   %w[ en:ciders en:non-alcoholic-ciders ] ],
      [ :wine,    %w[ en:wines en:wine-based-drinks en:non-alcoholic-wines ] ],
      [ :soda,    %w[ en:root-beers en:ginger-beer en:tonic-water ] ],
      [ :beer,    %w[ en:beers en:non-alcoholic-beers ] ],
      [ :liquor,  %w[ en:liqueurs en:hard-liquors en:distilled-beverages ] ],
      [ :energy,  %w[ en:energy-drinks ] ],
      [ :water,   %w[ en:waters ] ],
      [ :soda,    %w[ en:sodas en:colas en:lemonades en:tonic-water ] ],
      [ :juice,   %w[ en:fruit-juices en:fruit-nectars en:juices-and-nectars ] ],
      [ :tea,     %w[ en:iced-teas ] ]
    ].freeze

    # Nothing in them but water and sugar: no ABV on the label means 0, not
    # unknown — unless the row also says it is alcoholic. For the rest, no ABV
    # means we do not know.
    SOFT = %i[ water soda juice energy tea ].freeze
    SPIRITS = %i[ cachaca tequila vodka gin rum whisky cognac ].freeze

    # People type labels, and some numbers contradict the rest of the row. The
    # most ABV each kind can have: above it, the number is unknown, not a fact
    # (a 3% Coca-Cola, a 24.5% IPA, a 24% mineral water are typos).
    MAX_ACL = { beer: 20, wine: 25, cider: 15 }.merge(SOFT.to_h { |kind| [ kind, 1.2 ] }).freeze

    # packaging_tags mixes shapes and materials.
    CANS    = %w[ en:can en:drink-can en:aluminium-can en:metal-can en:steel-can ].freeze
    GLASS   = %w[ en:glass en:glass-bottle en:clear-glass en:coloured-glass en:green-glass en:brown-glass ].freeze
    PLASTIC = %w[ en:plastic en:plastic-bottle en:pet-bottle en:pet en:pet-1-polyethylene-terephthalate ].freeze
    BOTTLES = %w[ en:bottle ].freeze
    METAL   = %w[ en:aluminium en:metal ].freeze

    # ml per unit
    UNITS = {
      "ml" => 1, "cl" => 10, "dl" => 100,
      "l" => 1000, "lt" => 1000, "lts" => 1000,
      "litre" => 1000, "litres" => 1000, "liter" => 1000, "liters" => 1000,
      "litro" => 1000, "litros" => 1000,
      "oz" => 29.5735, "floz" => 29.5735,
      "gal" => 3785.41, "gallon" => 3785.41, "gallons" => 3785.41, "qt" => 946.353, "quart" => 946.353, "quarts" => 946.353
    }.freeze

    # A number no digit, slash, separator or exponent runs into: "1/2 L" is no "2 L".
    # (Each piece carries its own /i: an interpolated regexp keeps its own flags.)
    AMOUNT = %r{(?<![\d/.,eE])(\d+(?:[.,]\d+)?)}
    UNIT   = /(ml|cl|dl|litres?|liters?|litros?|lts?|l|fl\.?\s*oz|oz|gal(?:lons?)?|qt|quarts?)\b/i
    VOLUME = /#{AMOUNT}\s*#{UNIT}/i
    # "6 x 330 ml", "6 latas de 350 ml", "Pack 12 un 350ml"; and "330 ml x 6".
    UNITS_WORD = /x|×|\*|latas?|latinhas?|garrafas?|cans?|bottles?|bouteilles?|botellas?|un\.?|unidades?|units?/i
    COUNT_FIRST = /(?<![\d.,])(\d+)\s*(?:#{UNITS_WORD})\s*(?:de\s+|of\s+)?#{VOLUME}/i
    COUNT_AFTER = /#{VOLUME}\s*[x×*]\s*(\d+)\b/i
    # Below a miniature's 20 ml a drink's size is a typo: "0,33 cl" for 0,33 l.
    MIN_ML = 20
    MAX_ML = 30_000

    module_function

    def map(row)
      code = Ean.normalize(row["code"]) or return
      tags = Array(row["categories_tags"])
      return unless tags.intersect?(ROOTS)

      kind = kind(tags) or return
      kind, acl = plausible(kind, acl(row, kind, tags))
      name = translations(row, "product_name")
      return if name.empty?

      info = translations(row, "generic_name")
      ml, count = volume(row["quantity"], row["product_quantity"], row["product_quantity_unit"])

      attrs = {
        code: code,
        name_translations: name,
        kind: kind,
        pack: pack(row, name, count),
        size: ml&.round&.then { |n| n if n.between?(MIN_ML, MAX_ML) },
        acl: acl,
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

    # An alcoholic row that lands on a soft kind — an alcopop filed under sodas
    # — is a ready-to-drink, not a soda.
    def kind(tags)
      kind = KINDS.find { |_, wanted| tags.intersect?(wanted) }&.first
      SOFT.include?(kind) && tags.include?(ALCOHOLIC) ? :mixed : kind
    end

    # A spirit under 15% is a ready-to-drink (a Suntory Highball, a vodka
    # seltzer: spirits start at 15%). An ABV past what the kind can hold is
    # dropped, the kind kept.
    def plausible(kind, acl)
      return [ :mixed, acl ] if SPIRITS.include?(kind) && acl && acl > 0.5 && acl < 15
      return [ kind, nil ] if acl && MAX_ACL[kind] && acl > MAX_ACL[kind]

      [ kind, acl ]
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

    # [ml of one unit, units in the pack] from the label's own words — "350 ml",
    # "1,5 L", "33cl", "6 x 330 ml", "330 ml x 6" — and, when the words say
    # nothing usable, from product_quantity (OFF's total, in ml).
    def volume(quantity, total = nil, unit = nil)
      text = quantity.to_s
      ml, count =
        if (m = text.match(COUNT_FIRST)) then [ to_ml(m[2], m[3]), m[1].to_i ]
        elsif (m = text.match(COUNT_AFTER)) then [ to_ml(m[1], m[2]), m[3].to_i ]
        elsif (m = text.match(VOLUME)) then [ to_ml(m[1], m[2]), 1 ]
        else [ nil, 1 ]
        end
      count = 1 if count < 1

      total = unit.to_s.downcase == "ml" ? number(total) : nil
      if total && total >= 1
        if ml.nil?
          ml = total / count
        elsif count == 1 && total >= 2 * ml && (total / ml - (total / ml).round).abs < 0.01
          count = (total / ml).round # a case whose words name only the can
        end
      end
      [ ml, count ]
    end

    # "1.500 ml" is fifteen hundred: a dot or comma before exactly three digits
    # of millilitres groups thousands. "1,5 l" is one and a half.
    def to_ml(amount, unit)
      factor = UNITS[unit.downcase.delete(" .")] or return
      amount = amount.delete(".,") if factor == 1 && amount.match?(/\A[1-9]\d{0,2}[.,]\d{3}\z/)
      ml = amount.tr(",", ".").to_f * factor
      ml if ml.finite? && ml >= 1
    end

    def pack(row, names, count)
      return :kit if count > 1

      tags = Array(row["packaging_tags"])
      return :can if tags.intersect?(CANS)
      return :grf if tags.intersect?(GLASS)
      return :pet if tags.intersect?(PLASTIC)
      return :grf if tags.intersect?(BOTTLES)
      return :can if tags.intersect?(METAL)

      # Only words that cannot mean anything else: a "Can Blau" is a cava and a
      # "Pet-Nat" a wine, so "can" and "pet" in lower case prove nothing.
      text = names.values.join(" ")
      case text
      when /\b(lata|latinha)\b/i then :can
      when /\b(garrafa|long ?neck)\b/i then :grf
      when /\bPET\b/ then :pet
      end
    end

    # % by volume. Rows carry it as a nutriment, sometimes as text ("5 % vol").
    def acl(row, kind, tags)
      nutriments = row["nutriments"].is_a?(Hash) ? row["nutriments"] : {}
      value = %w[ alcohol_100g alcohol_value alcohol ].filter_map { |k| number(nutriments[k]) }.first
      if value.nil? && !tags.include?(ALCOHOLIC) && (SOFT.include?(kind) || tags.include?(NON_ALCOHOLIC))
        value = 0.0
      end
      value&.round(2) if value&.between?(0, 100)
    end

    # The front picture, as the API would link it. The jsonl export has no
    # image_*_url fields, only the `images` object they are built from — in
    # its old shape (images.front_pt.rev) or its new one (images.selected.front.pt.rev).
    def image(row)
      url = row["image_front_url"] || row["image_url"]
      return url.to_s if url.to_s.start_with?("http")

      images = row["images"]
      return unless images.is_a?(Hash)

      lang = (row["lang"] || row["lc"]).to_s
      fronts = images.dig("selected", "front")
      fronts = images.filter_map { |key, value| [ key.delete_prefix("front_"), value ] if key.start_with?("front_") }.to_h unless fronts.is_a?(Hash)
      lc, front = fronts.key?(lang) ? [ lang, fronts[lang] ] : fronts.first
      rev = front.is_a?(Hash) && front["rev"]
      return unless lc && rev.to_s.match?(/\A\d+\z/)

      "#{IMAGES}/#{image_path(row['code'])}/front_#{lc}.#{rev}.400.jpg"
    end

    # OFF's folder for a code: zeros off, padded to 13, split 3/3/3/rest.
    def image_path(code)
      code = code.to_s.sub(/\A0+/, "").rjust(13, "0")
      code.match(/\A(.{3})(.{3})(.{3})(.*)\z/).captures.join("/")
    end

    # "en:brazil" => "brazil". Only the taxonomy's own ids — English, lower
    # case, hyphens: a tag OFF could not place keeps its contributor's words
    # ("fr:France - La Réunion", "en:Scotland") and is no country or category
    # anyone can rely on.
    def slugs(tags)
      Array(tags).filter_map do |tag|
        slug = tag.to_s.delete_prefix("en:")
        slug if tag.to_s.start_with?("en:") && slug.match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/)
      end
    end

    # The first number in a value: 4.8, "4,8", "5 % vol". nil for none, or for
    # something no label says (Infinity, 1e400).
    def number(value)
      unless value.is_a?(Numeric)
        text = value.to_s.strip.tr(",", ".")
        value = Float(text, exception: false) || text[/\d+(?:\.\d+)?/]&.to_f
      end
      value = value&.to_f
      value if value&.finite?
    end

    # Entries from a jsonl or jsonl.gz dump — a path or an open IO — one at a
    # time, so the whole of Open Food Facts never sits in memory. `countries`
    # keeps only rows sold there ("en:brazil"); `limit` stops after n entries.
    # A row that will not parse or map is skipped, never allowed to stop the rest.
    def each(source, countries: nil, limit: nil)
      return enum_for(:each, source, countries: countries, limit: limit) unless block_given?

      count = 0
      reading(source) do |io|
        io.each_line do |line|
          # Millions of rows are food. Skip them before paying for the parse.
          next unless line.include?("en:beverages") || line.include?(ALCOHOLIC)

          entry = begin
            row = JSON.parse(line.scrub)
            next if countries && !Array(row["countries_tags"]).intersect?(countries)
            map(row)
          rescue JSON::ParserError, EncodingError, TypeError, NoMethodError, ArgumentError, FloatDomainError
            next
          end
          next unless entry

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
        Zlib::GzipReader.open(path, external_encoding: Encoding::UTF_8, &block)
      else
        File.open(path, "r:UTF-8", &block)
      end
    end
  end
end
