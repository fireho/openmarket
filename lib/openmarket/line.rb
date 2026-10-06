require "openmarket/ean"
require "openmarket/text"
require "openmarket/open_food_facts"

module Openmarket
  # One written line of a menu or price list in, the product it names out, so
  # a bar pastes its list instead of typing each item.
  #
  #   Line.parse("Cerveja Patagonia LATA 350ml  R$ 12,90")
  #   # => { type: "Drink", name: "Cerveja Patagonia", kind: :beer, pack: :can, size: 350, acl: nil, code: nil }
  #
  # What the line does not say stays nil, never guessed: "Heineken LN 330" is a
  # drink in a bottle, but no word in it says beer. The name is what the person
  # wrote, minus what was read out of it: pack, size, ABV, barcode and price.
  # The price is the bar's, not the product's, so it is read only to be dropped.
  # Size is ml for a drink and g for food; a line that is neither has none.
  # Plain Ruby, no Mongoid: the caller makes the document.
  module Line
    CUT = "\u0001" # where something was read out of the name

    # The words that name a kind, in pt, es and en, as people write them (they
    # are folded on load). Groups are tried in order: a cocktail before its
    # spirit, a liqueur before its whisky, a beer before the tequila it is
    # flavoured with, a drink before food ("Chocolate Stout" is a beer), a dish
    # before what is in it. Inside a group the word that comes first wins:
    # "picanha com fritas" is meat, "porção de picanha" a snack. A word inside
    # a longer one gives way to it: "água tônica" is no water, "ice tea" no
    # cocktail. Plurals in -s come free. Between a drink and a dish, a small
    # word says which is in which (see LINKS), and a weight says it is food.
    KINDS = [
      [ "Drink", mixed: "caipirinha, caipiroska, caipivodka, batida, mojito, negroni, spritz, daiquiri, sangria, " \
                        "cuba libre, moscow mule, piña colada, gin tônica, gin tonic, fernet con coca, fernet com coca, " \
                        "coquetel, coquetéis, cocktail, cóctel, drink, drinque, drink pronto, drinks prontos, hard seltzer, ice" ],
      [ "Drink", liquor: "licor, licores, liqueur, fernet, amaro, absinto, absinthe" ],
      [ "Drink", beer: "cerveja, cervejinha, cerveza, beer, chopp, chope, lager, pilsen, pilsner, ipa, apa, stout, porter, " \
                       "weiss, weisse, weizen, witbier, bock, ale" ],
      [ "Drink", cachaca: "cachaça, pinga, aguardente, caninha" ],
      [ "Drink", tequila: "tequila, mezcal" ],
      [ "Drink", vodka: "vodka, vodca" ],
      [ "Drink", gin: "gin, ginebra" ],
      [ "Drink", rum: "rum, ron" ],
      [ "Drink", whisky: "whisky, whiskey, whiskies, uísque, bourbon, scotch" ],
      [ "Drink", cognac: "conhaque, cognac, coñac, brandy" ],
      [ "Drink", cider: "sidra, cider" ],
      [ "Drink", wine: "vinho, vino, wine, chopp de vinho, espumante, champagne, champanhe, prosecco, frisante, lambrusco, " \
                       "malbec, cabernet, merlot, carménère, tannat, syrah, shiraz, chardonnay, sauvignon, pinot, torrontés, moscato" ],
      [ "Drink", energy: "energético, energy, energy drink, energizante, bebida energética" ],
      [ "Drink", soda: "refrigerante, refri, gaseosa, soda, soft drink, cola, guaraná, tônica, água tônica, tonic water, " \
                       "ginger ale, ginger beer, root beer" ],
      [ "Drink", juice: "suco, jugo, juice, néctar, zumo" ],
      [ "Drink", tea: "chá, chá gelado, tea, ice tea, iced tea, té helado" ],
      [ "Drink", water: "água, water" ],
      [ "Food", burger: "hambúrguer, hambúrgueres, hamburger, hamburguesa, burger, cheeseburger, " \
                        "x-burger, x-salada, x-bacon, x-egg, x-tudo" ],
      [ "Food", pizza: "pizza, calzone" ],
      [ "Food", sushi: "sushi, sashimi, temaki, uramaki, hossomaki, niguiri, nigiri, hot roll" ],
      [ "Food", pasta: "massa, macarrão, macarronada, espaguete, spaghetti, lasanha, lasagna, ravioli, nhoque, gnocchi, " \
                       "ñoquis, talharim, tallarines, fettuccine, penne, pasta" ],
      [ "Food", fast: "lanche, sanduíche, sandwich, hot dog, cachorro-quente, misto quente, bauru, beirute, wrap, burrito, " \
                      "taco, choripán, lomito, fast food" ],
      [ "Food", dessert: "sobremesa, postre, dessert, doce, chocolate, sorvete, helado, ice cream, pudim, flan, bolo, cake, " \
                         "brownie, cheesecake, mousse, brigadeiro, petit gâteau, alfajor, doce de leite, dulce de leche, bombom",
                snack: "petisco, porção, porções, snack, amendoim, maní, batata, batata doce, fritas, papas fritas, fries, " \
                       "nachos, azeitona, aceitunas, olives, antepasto, antipasto, picada, empanada, coxinha, bolinho, " \
                       "salgadinho, pipoca, pão de alho, onion rings, tábua de frios, isca, frango a passarinho, " \
                       "mandioca frita, aipim frito, wings",
                meat: "carne, picanha, steak, ribeye, bife, costela, costelinha, fraldinha, alcatra, maminha, cupim, " \
                      "linguiça, churrasco, asado, vacío, entraña, ribs" ],
      # Drinks that none of the kinds fit: still drinks, so "chocolate quente" is no dessert.
      [ "Drink", nil => "café, coffee, cappuccino, espresso, expresso, chocolate quente, hot chocolate, chocolate caliente, " \
                        "água de coco, coconut water, milkshake, milk shake" ]
    ].freeze

    # [pattern, rank, type, kind], the longest words first: they claim their
    # place in the line before a word inside them can.
    KEYWORDS = KINDS.each_with_index.flat_map do |(type, kinds), rank|
      kinds.flat_map do |kind, words|
        words.split(",").map { |word| [ Text.fold(word).split(/[^\p{Alnum}]+/).join(" "), rank, type, kind ] }
      end
    end.sort_by { |word, *| -word.size }.map { |word, *rest| [ /(?<![^ ])#{Regexp.escape(word)}s?(?![^ ])/, *rest ] }.freeze

    # The words that only say what kind of thing it is ("cerveja", "refrigerante"),
    # folded. A menu's "Cerveja Heineken" is the catalogue's "Heineken".
    KIND_WORDS = KINDS.flat_map { |_, kinds| kinds.values }.flat_map { |words| Text.tokens(words.split(",")) }.uniq.freeze

    # A kit is a kit whatever is in it; otherwise the first pack named. "can"
    # never as the first word (a "Can Blau" is a cava), "LN" only in capitals,
    # "pet" never in a pet-nat. Boxes and pieces leave the name but say no
    # pack: a "caixa" is a case of twelve or a carton of juice.
    # What a number right after the word is: how many ("Kit 6", "cx 12") or
    # the size of each ("LN 330", "Lata 350"), in the type's own unit.
    PACKS = [
      [ :kit, :count, /\b(?:kits?|packs?|six-?packs?|fardos?|pacotes?|pctes?|pcts?|engradados?)\b/i ],
      [ :pet, :size,  /\b(?:garrafas?\s+)?pet\b(?![\s-]*nat\b)/i ],
      [ :can, :size,  /\b(?:latas?|latinhas?|lat[aã]o|lat[õo]es)\b|(?<=[^\p{Alnum}])cans?\b/i ],
      [ :grf, :size,  /\b(?:garrafas?|garrafinhas?|grf|long[\s-]?necks?|botellas?|bottles?|litr[aã]o|litrinho|porr[oó]n(?:es)?|(?-i:LN))\b/i ],
      [ nil,  :count, /\b(?:caixas?|cx)\b/i ],
      [ nil,  :size,  /\b(?:caixinhas?|pc|pç)\b/i ]
    ].map { |pack, number, word| [ pack, number, /#{word}(?:\s*(?:de\s+)?(\d{1,4})(?![\d.,%\p{Alnum}]))?/i ] }.freeze
    DRINK_PACKS = %i[ grf pet ].freeze # nobody bottles a pizza; a can of olives exists

    # Volumes are read as Open Food Facts reads them, plus "cc": how Argentina
    # writes millilitres ("Quilmes 970 cc"). Weights here. An ounce is a fluid
    # ounce on a drink and a weight on food.
    GRAMS = {
      "g" => 1, "gr" => 1, "grs" => 1, "grama" => 1, "gramas" => 1, "gramo" => 1, "gramos" => 1, "gram" => 1, "grams" => 1,
      "kg" => 1000, "kgs" => 1000, "kilo" => 1000, "kilos" => 1000, "quilo" => 1000, "quilos" => 1000,
      "lb" => 453.592, "lbs" => 453.592, "oz" => 28.3495
    }.freeze
    MASS_UNIT = /kgs?|kilos?|quilos?|gramas?|gramos?|grams?|grs?|g|lbs?/i
    CC = /cc|cm3|cm³/i
    MEASURE = /#{OpenFoodFacts::AMOUNT}\s*(?:#{OpenFoodFacts::UNIT}|(#{MASS_UNIT}|#{CC})\b)/i
    # "6x350ml", "12 latas de 350 ml", "Pack 12 un 350ml"; and "350 ml x 6".
    # Only a plural or an "x" counts: a "Cachaça 51 Garrafa 965ml" is one bottle.
    EACH = /x|×|\*|latas|latinhas|garrafas|cans|bottles|botellas|un\.?|und\.?|unid\.?|unidades|units/i
    COUNTED = /(?<![\d.,])(\d+)\s*(?:#{EACH})\s*(?:de\s+|of\s+)?#{MEASURE}/i
    TIMES = /#{MEASURE}\s*[x×*]\s*(\d+)(?![\d.,])/i
    # "6 un", "c/ 12": how many, with no size.
    COUNT = %r{(?<![\d.,])(\d{1,3})\s*(?:un|und|unid|unidades?|units?)\b\.?|\bc/\s*(\d{1,3})(?![\d.,])}i
    MAX_SIZE = OpenFoodFacts::MAX_ML # ml or g: more than a keg is a typo

    # ABV: "4,8%", "40% vol", "5% álcool", "Alc. 4,5%", "ABV 5.2". Said with a
    # word it is always read; a bare "6,5%" only on a drink, under 100, and not
    # before a word: "100% natural", "50% suco", "30% off" are no ABV.
    ABV = %r{
      (?:\b(abv|alc|teor\s+alco[oó]lico|graduaci[oó]n)\.?\s*:?\s*)?
      (?<![\d.,])(\d{1,3}(?:[.,]\d{1,2})?)\s*(%)?
      (\s*(?:vol|abv|alc|[aá]lcool|alcohol|v/v)\b\.?(?:\s*/\s*vol\b\.?)?)?
    }xi

    # Prices: "R$ 12,90", "$ 1.500", "US$ 5", "€4"; a last number with cents
    # or thousands ("12,90", "1.500"); a last number in a column of its own.
    PRICE = /(?:R\$|US\$|U\$S|AR\$|\$|€|£|\b(?:BRL|USD|ARS|EUR)\b)\s*\d[\d.,]*(?<![.,])(?:[.,]-)?/i
    SEPARATORS = Regexp.escape("-–—|/:;,•·")
    LAST_PRICE = /(?<![\d.,])(?:\d{1,3}(?:[.,]\d{3})+(?:[.,]\d{2})?|\d+[.,]\d{2})(?=[\s#{SEPARATORS}#{CUT}]*\z)/
    COLUMN_PRICE = /\|\s*\d+(?:[.,]\d{1,2})?(?=[\s#{CUT}]*\z)/

    # A barcode in the line: 8, 12, 13 or 14 digits that pass the check digit.
    CODE = /(?:\b(?:ean|gtin|c[oó]d(?:igo)?)\.?\s*:?\s*)?(?<![\d.,])(\d{8}(?:\d{4,6})?)(?![\d.,])/i

    # Small words that tie a word to the one before it. Between a drink and a
    # dish, the one tied is what the other is made with: "Batida de amendoim"
    # is a drink, "Bombom de licor" a sweet. Some say a dish was cooked in the
    # drink, so "Frango ao vinho" and "Pollo a la cerveza" are dishes even
    # though no word names one.
    LINKS = "de|da|do|das|dos|com|con|em|en|na|no|nas|nos|ao|aos|al|a la|por|in|with|of"
    COOKED_IN = "na|no|nas|nos|ao|aos|al|a la|in"
    TIED = /(?:\A| )(?:#{LINKS}) \z/ # on folded words
    COOKED = /(?:\A| )(?:#{COOKED_IN}) \z/

    # A small word a cut leaves hanging. One just before a cut went with what
    # was cut: "Coca-Cola garrafa de 2L", "Cerveja de 600ml gelada". One just
    # after a cut goes with what follows ("Água 500ml com gás" is sparkling),
    # unless nothing comes before it: "Lata de Coca-Cola" is a Coca-Cola.
    EDGE = /[\s#{SEPARATORS}#{CUT}]/
    LINK = /\b(?:#{LINKS})\b/i
    DANGLING = /#{LINK}\s*(?=#{CUT})|\A#{EDGE}*#{CUT}(?:#{EDGE}|#{LINK})*/

    module_function

    # `section` is the [type, kind] of the heading the line sits under, for a
    # line whose own words name nothing; parse_all passes it.
    def parse(text, section: nil)
      line = clean(text)

      code = nil
      line = line.gsub(CODE) { |found| !code && (code = Ean.normalize($1)) ? CUT : found }
      line = line.gsub(PRICE, CUT).sub(LAST_PRICE, CUT).sub(COLUMN_PRICE, CUT)

      line, count, amount, unit = measure(line)
      line = line.gsub(COUNT) do
        count = ($1 || $2).to_i if count == 1
        CUT
      end

      pack = nil
      PACKS.each do |found, means, pattern|
        line = line.gsub(pattern) do
          pack ||= found
          number = $1&.to_i
          if number && means == :count && count == 1 && number.between?(2, 99) then count = number
          elsif number && means == :size && amount.nil? && number.between?(50, 5000) then amount = number.to_s
          elsif number then next "#{CUT} #{number}" # not a size or a count anyone sells: the name's
          end
          CUT
        end
      end

      line, acl = abv(line)
      measured = unit_type(unit)
      hit = kind(line, weighed: measured == "Food")
      type, kind = hit
      type ||= "Drink" if acl
      type ||= measured
      type ||= "Drink" if DRINK_PACKS.include?(pack)
      # Nobody weighs a drink: "Café 500g" is beans or a dish, and the line does
      # not say which. Food is sometimes measured ("Sorvete 1,5 L"): it stays
      # food, with no size, as its size is in grams.
      type = kind = nil if type == "Drink" && measured == "Food"
      type, kind = section if hit.nil? && section && [ nil, section.first ].include?(type) && line.match?(/\p{L}/)
      line, acl = abv(line, bare: true) if type == "Drink" && acl.nil?

      {
        type: type,
        name: tidy(line),
        kind: kind,
        pack: (count > 1 ? :kit : pack unless type == "Food"),
        size: (size(amount, unit, type) if amount && type),
        acl: (acl if type == "Drink"),
        code: code
      }
    end

    # Many lines, a pasted menu: one result per product line, with its number
    # and text so a person can find it, and an `error` when it named nothing.
    # Blank lines and comments (# or //) are skipped. A heading ("Cervejas:",
    # "== Vinhos ==") is no product, but the lines under it that name no kind
    # of their own are what it names.
    def parse_all(text)
      section = nil
      (text.respond_to?(:each_line) ? text : text.to_s).each_line.with_index(1).filter_map do |raw, number|
        line = clean(raw)
        next if line.start_with?("#", "//") || !line.match?(/[\p{L}\p{N}]/)

        if heading?(line)
          section = heading(line)
          next
        end

        found = parse(line, section: section)
        found[:error] = "no name" unless found[:name]
        { line: number, text: utf8(raw).strip, **found }
      end
    end

    # [type, kind] the words name — kind nil for a drink none of the kinds
    # fit — or nil when they name nothing. A line `weighed` names a dish
    # rather than the drink in it: "Bombom de licor 200g".
    def kind(text, weighed: false)
      found = hits(text)
      food = found.select { |_, _, type| type == "Food" }
      found = food if weighed && food.any?
      untied = found.reject(&:last).map { |hit| hit[2] } # the types named by a word nothing ties
      best = found.min_by { |rank, at, type, _, tied| [ tied && (untied - [ type ]).any? ? 1 : 0, rank, at ] }
      best&.values_at(2, 3)
    end

    # [rank, at, type, kind, tied] for each word that names a kind: its group,
    # where it is, and whether a small word ties it to the word before. A drink
    # a dish was cooked in ("ao vinho") stands for that dish, of no kind.
    def hits(text)
      words = Text.fold(text).split(/[^\p{Alnum}]+/).reject(&:empty?).join(" ")
      left = words.dup
      found = []
      KEYWORDS.each do |pattern, rank, type, kind|
        left = left.gsub(pattern) do |word|
          at = $~.begin(0)
          before = words[0, at]
          if type == "Drink" && before.match?(COOKED) then found << [ KINDS.size, at, "Food", nil, true ]
          else found << [ rank, at, type, kind, before.match?(TIED) ]
          end
          " " * word.size
        end
      end
      found
    end

    # What a heading names: its one kind ("Cervejas:"), only its type when it
    # names more ("Águas e Refrigerantes:" are drinks of no one kind), and
    # nothing when it names drinks and dishes.
    def heading(line)
      named = hits(line).map { |_, _, type, kind, _| [ type, kind ] }.uniq
      return named.first if named.size <= 1
      [ named.first.first, nil ] if named.map(&:first).uniq.size == 1
    end

    # "Cervejas:", "== Vinhos ==", "**Porções**": a title, with no number in it.
    def heading?(line)
      !line.match?(/\d/) && (line.end_with?(":") || line.match?(/\A[-=*_~]{2,}.+[-=*_~]{2,}\z/))
    end

    # One line, its columns marked: a tab or dot leaders part a name from its
    # price. A list's bullet or number is no part of the name.
    def clean(text)
      utf8(text).unicode_normalize(:nfc).tr(CUT, " ")
                .gsub(/\t|\.{3,}|…+/, " | ").gsub(/[[:space:]]+/, " ").strip
                .sub(/\A(?:[-*•·]|\d{1,3}[.)])\s+/, "")
    end

    # A list saved by a spreadsheet on Windows is Windows-1252 more often than
    # not: read its bytes as that rather than drop the accents ("gua" for "Água").
    # Excel starts a UTF-8 file with a byte order mark; it is no part of a name.
    def utf8(text)
      text = text.to_s.dup
      text.force_encoding(Encoding::UTF_8) if [ Encoding::BINARY, Encoding::US_ASCII ].include?(text.encoding)
      text = text.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "") unless text.encoding == Encoding::UTF_8
      unless text.valid_encoding?
        text = text.force_encoding(Encoding::Windows_1252).encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "")
      end
      text.delete("﻿")
    end

    # [line, count, amount, unit]: the first size the line says, cut out, and
    # any other cut too ("2 L (2000 ml)" says nothing new).
    def measure(line)
      if (m = line.match(COUNTED)) then count, amount, unit = m[1].to_i, m[2], m[3] || m[4]
      elsif (m = line.match(TIMES)) then amount, unit, count = m[1], m[2] || m[3], m[4].to_i
      elsif (m = line.match(MEASURE)) then amount, unit, count = m[1], m[2] || m[3], 1
      else return [ line, 1, nil, nil ]
      end
      unit = "ml" if unit.match?(/\A#{CC}\z/) # a cubic centimetre is a millilitre
      [ "#{m.pre_match}#{CUT}#{m.post_match}".gsub(MEASURE, CUT), [ count, 1 ].max, amount, unit ]
    end

    # [line, acl]: the first ABV said outright, cut out — or, with `bare`, the
    # first plain one.
    def abv(line, bare: false)
      acl = nil
      line = line.gsub(ABV) do |found|
        m = $~
        value = m[2].tr(",", ".").to_f
        said = m[1] || (m[3] && m[4])
        plain = bare && m[3] && !m[4] && value < 100 && !m.post_match.match?(/\A\s*\p{L}/)
        next found unless acl.nil? && (said || plain) && value <= 100

        acl = value.round(2)
        CUT
      end
      [ line, acl ]
    end

    def unit_type(unit)
      unit = unit.to_s.downcase.delete(" .")
      return if unit.empty? || unit == "oz" # an ounce of what?
      return "Drink" if OpenFoodFacts::UNITS.key?(unit)
      "Food" if GRAMS.key?(unit)
    end

    # ml for a drink, g for food; a number with no unit is already in it.
    def size(amount, unit, type)
      value =
        if unit.nil? then amount.to_f
        elsif type == "Drink" then OpenFoodFacts.to_ml(amount, unit)
        elsif type == "Food" then grams(amount, unit)
        end
      value&.round&.then { |n| n if n.between?(1, MAX_SIZE) }
    end

    # As OpenFoodFacts.to_ml: "1.000 g" is a thousand, "1,5 kg" one and a half.
    def grams(amount, unit)
      factor = GRAMS[unit.downcase] or return
      amount = amount.delete(".,") if factor == 1 && amount.match?(/\A[1-9]\d{0,2}[.,]\d{3}\z/)
      amount.tr(",", ".").to_f * factor
    end

    # What is left once everything read is cut: the words people wrote, without
    # the separators and small words that hung on what was cut.
    def tidy(line)
      name = line.gsub(DANGLING, "")
      name = name.gsub(/[\s#{SEPARATORS}#{CUT}]*#{CUT}[\s#{SEPARATORS}#{CUT}]*/) do |run|
        (separator = run[/[#{SEPARATORS}]/]) ? " #{separator} " : " "
      end
      name = name.gsub(/\([\s#{SEPARATORS}]*\)|\[[\s#{SEPARATORS}]*\]/, " ")
      name = name.gsub(/\s+/, " ").gsub(/\A[\s#{SEPARATORS}]+|[\s#{SEPARATORS}]+\z/, "")
      name unless name.empty?
    end
  end
end
