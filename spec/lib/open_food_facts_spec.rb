require "standalone_helper"
require "stringio"
require "json"

RSpec.describe Openmarket::OpenFoodFacts do
  let(:brahma) do
    {
      "code" => "7891991010023", "lang" => "pt",
      "product_name" => "Cerveja Brahma Chopp", "product_name_en" => "Brahma Draft Beer",
      "generic_name" => "Cerveja pilsen",
      "brands" => "Brahma, Ambev", "quantity" => "350 ml",
      "categories_tags" => %w[ en:beverages en:alcoholic-beverages en:beers en:lagers ],
      "packaging_tags" => %w[ en:can ], "countries_tags" => %w[ en:brazil ],
      "nutriments" => { "alcohol_100g" => 4.8 },
      "image_front_url" => "https://images.openfoodfacts.org/brahma.jpg"
    }
  end

  describe ".map" do
    subject(:entry) { described_class.map(brahma) }

    it "makes a drink entry keyed by the code" do
      expect(entry).to include(code: "7891991010023", type: "Drink", brand: "Brahma")
    end

    it "carries what the label says" do
      expect(entry[:attrs]).to include(
        kind: :beer, pack: :can, size: 350, acl: 4.8,
        quantity: "350 ml", countries: %w[ brazil ], source: "off",
        image: "https://images.openfoodfacts.org/brahma.jpg"
      )
    end

    it "keeps the names by language" do
      expect(entry[:attrs][:name_translations]).to eq("pt" => "Cerveja Brahma Chopp", "en" => "Brahma Draft Beer")
      expect(entry[:attrs][:info_translations]).to eq("pt" => "Cerveja pilsen")
    end

    it "keeps only the taxonomy's own countries and categories" do
      row = brahma.merge("countries_tags" => %w[ en:brazil fr:France\ -\ La\ Réunion es:mundial en:Scotland ],
                         "categories_tags" => %w[ en:beverages en:beers fr:bieres-artisanales ])
      expect(described_class.map(row)[:attrs]).to include(countries: %w[ brazil ], tags: %w[ beverages beers ])
    end

    it "keeps the categories as slugs" do
      expect(entry[:attrs][:tags]).to eq(%w[ beverages alcoholic-beverages beers lagers ])
    end

    it "files a UPC-A under its EAN-13" do
      row = brahma.merge("code" => "036000291452")
      expect(described_class.map(row)[:code]).to eq("0036000291452")
    end

    it "puts a name with no translations under the row's language" do
      row = { "code" => "4006381333931", "lc" => "pt", "product_name" => "Guaraná", "categories_tags" => %w[ en:beverages en:sodas ] }
      expect(described_class.map(row)[:attrs][:name_translations]).to eq("pt" => "Guaraná")
    end

    describe "image" do
      it "builds the front picture from the images of the jsonl export" do
        row = brahma.except("image_front_url").merge("images" => { "front_pt" => { "rev" => "12" }, "1" => {} })
        expect(described_class.map(row)[:attrs][:image])
          .to eq("https://images.openfoodfacts.org/images/products/789/199/101/0023/front_pt.12.400.jpg")
      end

      it "reads the newer images shape too, in any language" do
        row = brahma.except("image_front_url").merge("images" => { "selected" => { "front" => { "fr" => { "rev" => 3 } } } })
        expect(described_class.map(row)[:attrs][:image]).to end_with("/front_fr.3.400.jpg")
      end

      it "pads a short code to OFF's folder" do
        expect(described_class.image_path("96385074")).to eq("000/009/638/5074")
      end

      it "is nil without a front picture" do
        expect(described_class.map(brahma.except("image_front_url").merge("images" => { "1" => {} }))[:attrs][:image]).to be_nil
      end
    end

    describe "what it will not take" do
      it "skips food" do
        expect(described_class.map(brahma.merge("categories_tags" => %w[ en:breakfasts ]))).to be_nil
      end

      it "skips a drink it cannot place" do
        expect(described_class.map(brahma.merge("categories_tags" => %w[ en:beverages en:teas ]))).to be_nil
      end

      it "skips a code that is no barcode" do
        expect(described_class.map(brahma.merge("code" => "7891991010024"))).to be_nil
        expect(described_class.map(brahma.merge("code" => nil))).to be_nil
      end

      it "skips a row with no name" do
        expect(described_class.map(brahma.merge("product_name" => " ", "product_name_en" => nil))).to be_nil
      end
    end

    describe "alcohol" do
      it "is unknown, not zero, when a beer has no ABV" do
        row = brahma.merge("nutriments" => {})
        expect(described_class.map(row)[:attrs][:acl]).to be_nil
      end

      it "is zero for a soda with no ABV" do
        row = brahma.merge("categories_tags" => %w[ en:beverages en:sodas ], "nutriments" => nil)
        expect(described_class.map(row)[:attrs][:acl]).to eq(0.0)
      end

      it "reads a number written with a comma" do
        row = brahma.merge("nutriments" => { "alcohol_100g" => "4,75" })
        expect(described_class.map(row)[:attrs][:acl]).to eq(4.75)
      end

      it "is unknown, not zero, for an alcopop with no ABV" do
        row = brahma.merge("categories_tags" => %w[ en:beverages en:alcoholic-beverages en:carbonated-drinks en:sodas ], "nutriments" => {})
        expect(described_class.map(row)[:attrs]).to include(kind: :mixed, acl: nil)
      end

      it "is zero for a beer sold as alcohol-free" do
        row = brahma.merge("categories_tags" => %w[ en:beverages en:non-alcoholic-beverages en:non-alcoholic-beers ], "nutriments" => {})
        expect(described_class.map(row)[:attrs]).to include(kind: :beer, acl: 0.0)
      end

      it "reads it written as text" do
        row = brahma.merge("nutriments" => { "alcohol" => "5 % vol" })
        expect(described_class.map(row)[:attrs][:acl]).to eq(5.0)
      end

      describe "that the rest of the row contradicts" do
        def mapped(tags, abv) = described_class.map(brahma.merge("categories_tags" => [ "en:beverages", *tags ], "nutriments" => { "alcohol_100g" => abv }))[:attrs]

        it "files a spirit under 15% as a ready-to-drink" do
          expect(mapped(%w[ en:alcoholic-beverages en:whisky ], 9)).to include(kind: :mixed, acl: 9.0)
          expect(mapped(%w[ en:alcoholic-beverages en:vodka ], 40)).to include(kind: :vodka, acl: 40.0)
        end

        it "drops an ABV the kind cannot have" do
          expect(mapped(%w[ en:carbonated-drinks en:sodas ], 3)).to include(kind: :soda, acl: nil)
          expect(mapped(%w[ en:waters ], 24.2)).to include(kind: :water, acl: nil)
          expect(mapped(%w[ en:alcoholic-beverages en:beers ], 24.5)).to include(kind: :beer, acl: nil)
          expect(mapped(%w[ en:alcoholic-beverages en:wines ], 40)).to include(kind: :wine, acl: nil)
        end

        it "keeps a strong beer and a strong liqueur" do
          expect(mapped(%w[ en:alcoholic-beverages en:beers ], 11)).to include(acl: 11.0)
          expect(mapped(%w[ en:alcoholic-beverages en:liqueurs ], 52)).to include(acl: 52.0)
        end
      end

      it "ignores nonsense" do
        row = brahma.merge("nutriments" => { "alcohol_100g" => 480 })
        expect(described_class.map(row)[:attrs][:acl]).to be_nil
      end
    end

    describe "kind" do
      def kind_of(*tags)
        described_class.map(brahma.merge("categories_tags" => [ "en:beverages", *tags ], "nutriments" => {}))&.dig(:attrs, :kind)
      end

      # Tag sets as OFF writes them: every ancestor of the category is there.
      SPIRITS = %w[ en:alcoholic-beverages en:distilled-beverages en:hard-liquors en:eaux-de-vie ].freeze

      it "picks the narrow before the wide" do
        expect(kind_of(*SPIRITS, "en:gins")).to eq(:gin)
        expect(kind_of(*SPIRITS, "en:vodka")).to eq(:vodka)
        expect(kind_of(*SPIRITS, "en:whisky", "en:scotch-whisky")).to eq(:whisky)
        expect(kind_of(*SPIRITS)).to eq(:liquor)
        expect(kind_of("en:carbonated-drinks", "en:soft-drinks", "en:sodas", "en:energy-drinks")).to eq(:energy)
      end

      it "knows the kinds a bar sells" do
        expect(kind_of("en:alcoholic-beverages", "en:wines")).to eq(:wine)
        expect(kind_of("en:alcoholic-beverages", "en:spirits", "en:cachaca")).to eq(:cachaca)
        expect(kind_of("en:waters", "en:spring-waters", "en:mineral-waters")).to eq(:water)
        expect(kind_of("en:plant-based-beverages", "en:juices-and-nectars", "en:fruit-juices")).to eq(:juice)
        expect(kind_of("en:alcoholic-beverages", "en:ciders")).to eq(:cider)
        expect(kind_of("en:tea-based-beverages", "en:iced-teas")).to eq(:tea)
      end

      it "files a sparkling water as water, not soda" do
        expect(kind_of("en:carbonated-drinks", "en:waters", "en:mineral-waters", "en:carbonated-waters")).to eq(:water)
      end

      it "files a tonic as a soda, even tagged as a water" do
        expect(kind_of("en:waters", "en:carbonated-drinks", "en:sodas", "en:tonic-water")).to eq(:soda)
      end

      it "files a ginger beer as a soda, not a beer" do
        expect(kind_of("en:non-alcoholic-beverages", "en:non-alcoholic-beers", "en:ginger-beer")).to eq(:soda)
      end

      it "files an alcopop as a ready-to-drink, never a soda" do
        expect(kind_of("en:alcoholic-beverages", "en:premixed-alcoholic-beverages")).to eq(:mixed)
        expect(kind_of("en:alcoholic-beverages", "en:hard-seltzers")).to eq(:mixed)
        expect(kind_of("en:alcoholic-beverages", "en:carbonated-drinks", "en:sodas")).to eq(:mixed)
      end

      it "skips what is under beverages but no drink a bar pours" do
        expect(kind_of("en:hot-beverages", "en:plant-based-beverages", "en:teas")).to be_nil
        expect(kind_of("en:coffee-drinks")).to be_nil
      end
    end

    describe "pack" do
      def pack_of(row) = described_class.map(brahma.merge(row))[:attrs][:pack]

      it { expect(pack_of("packaging_tags" => %w[ en:bottle en:glass ])).to eq(:grf) }
      it { expect(pack_of("packaging_tags" => %w[ en:bottle en:plastic-bottle ])).to eq(:pet) }
      it { expect(pack_of("packaging_tags" => %w[ en:bottle ])).to eq(:grf) }
      it { expect(pack_of("packaging_tags" => %w[ en:bottle en:plastic ])).to eq(:pet) }
      it { expect(pack_of("packaging_tags" => %w[ en:drink-can en:aluminium ])).to eq(:can) }
      it { expect(pack_of("quantity" => "330 ml x 6")).to eq(:kit) }
      it { expect(pack_of("quantity" => "6 x 350 ml")).to eq(:kit) }

      it "reads the name when the tags say nothing" do
        expect(pack_of("packaging_tags" => [], "product_name" => "Cerveja Amstel Lata", "lang" => "pt")).to eq(:can)
      end

      it "is nil, not a guess, when nothing says" do
        expect(pack_of("packaging_tags" => [], "product_name" => "Cerveja X")).to be_nil
      end

      it "is not fooled by names that only look like packs" do
        expect(pack_of("packaging_tags" => [], "product_name" => "Pet-Nat Rosé", "product_name_en" => nil)).to be_nil
        expect(pack_of("packaging_tags" => [], "product_name" => "Can Blau", "product_name_en" => nil)).to be_nil
        expect(pack_of("packaging_tags" => [], "product_name" => "Refrigerante PET 2L", "product_name_en" => nil)).to eq(:pet)
      end

      it "is not fooled by a plastic cap on a glass bottle" do
        expect(pack_of("packaging_tags" => %w[ en:bottle en:glass en:plastic ])).to eq(:grf)
      end
    end
  end

  describe ".volume" do
    {
      "350 ml" => [ 350, 1 ], "1,5 L" => [ 1500, 1 ], "33cl" => [ 330, 1 ], "0,355 l" => [ 355, 1 ],
      "2 litros" => [ 2000, 1 ], "6 x 330 ml" => [ 330, 6 ], "12x350ml" => [ 350, 12 ], "12 × 33 cl" => [ 330, 12 ]
    }.each do |text, (ml, count)|
      it "reads #{text.inspect}" do
        got_ml, got_count = described_class.volume(text)
        expect(got_ml.round).to eq(ml)
        expect(got_count).to eq(count)
      end
    end

    {
      "1.500 ml" => [ 1500, 1 ], "1.000ml" => [ 1000, 1 ], "1,000 mL" => [ 1000, 1 ], "1,5 L" => [ 1500, 1 ],
      "330 ml x 6" => [ 330, 6 ], "33 CL X 24" => [ 330, 24 ], "6 latas de 350 ml" => [ 350, 6 ], "Pack 12 un 350ml" => [ 350, 12 ]
    }.each do |text, (ml, count)|
      it "reads #{text.inspect}" do
        got_ml, got_count = described_class.volume(text)
        expect([ got_ml.round, got_count ]).to eq([ ml, count ])
      end
    end

    it "does not read half a litre as two" do
      expect(described_class.volume("1/2 L").first).to be_nil
    end

    it "falls back to OFF's total in ml, and counts a case by it" do
      expect(described_class.volume("", "750", "ml")).to eq([ 750.0, 1 ])
      expect(described_class.volume("330 ml", "1980", "ml")).to eq([ 330.0, 6 ])
      expect(described_class.volume("", "500", "g")).to eq([ nil, 1 ])
    end

    it "takes no infinite bottle" do
      expect(described_class.volume("", "1e400", "ml")).to eq([ nil, 1 ])
    end

    it "reads gallons and quarts" do
      expect(described_class.volume("4 x 1 Gallon").then { |ml, count| [ ml.round, count ] }).to eq([ 3785, 4 ])
      expect(described_class.volume("2 qt").first.round).to eq(1893)
    end

    it "takes no size from a typo below a miniature" do
      row = brahma.merge("quantity" => "0,33 cl", "product_quantity" => nil)
      expect(described_class.map(row)[:attrs][:size]).to be_nil
    end

    it "reads fluid ounces" do
      expect(described_class.volume("12 fl oz").first.round).to eq(355)
    end

    it "has no volume for a weight, or nothing" do
      expect(described_class.volume("500 g").first).to be_nil
      expect(described_class.volume(nil).first).to be_nil
    end

    it "does not read the l of a word" do
      expect(described_class.volume("350 lata").first).to be_nil
    end
  end

  describe ".each" do
    let(:food) { { "code" => "4006381333931", "product_name" => "Granola", "categories_tags" => %w[ en:breakfasts ] } }
    let(:cola) do
      { "code" => "5901234123457", "lc" => "en", "product_name" => "Cola", "quantity" => "330 ml",
        "categories_tags" => %w[ en:beverages en:sodas ], "countries_tags" => %w[ en:france ] }
    end
    let(:lines) { [ food, brahma, cola ].map(&:to_json).join("\n") + "\nnot json {en:beverages\n" }

    it "streams the drinks out of a dump and skips the rest" do
      codes = described_class.each(StringIO.new(lines)).map { |entry| entry[:code] }
      expect(codes).to eq(%w[ 7891991010023 5901234123457 ])
    end

    it "keeps only the countries asked for" do
      codes = described_class.each(StringIO.new(lines), countries: %w[ en:brazil ]).map { |entry| entry[:code] }
      expect(codes).to eq(%w[ 7891991010023 ])
    end

    it "stops at the limit" do
      expect(described_class.each(StringIO.new(lines), limit: 1).count).to eq(1)
    end

    it "maps a row with an infinite quantity, without a size" do
      broken = brahma.merge("code" => "4006381333931", "quantity" => "", "product_quantity" => "PQ", "product_quantity_unit" => "ml")
      line = broken.to_json.sub('"PQ"', "1e400") # parses to Infinity

      expect(described_class.each(StringIO.new(line)).first[:attrs][:size]).to be_nil
    end

    it "skips a row that breaks the mapper and goes on" do
      allow(described_class).to receive(:map).and_call_original
      allow(described_class).to receive(:map).with(hash_including("code" => "7891991010023")).and_raise(TypeError)

      codes = described_class.each(StringIO.new(lines)).map { |entry| entry[:code] }
      expect(codes).to eq(%w[ 5901234123457 ])
    end

    it "reads a file as UTF-8 whatever the shell's locale" do
      path = File.join(Dir.mktmpdir, "off.jsonl")
      File.write(path, brahma.merge("product_name" => "Antártica").to_json + "\n")
      external = Encoding.default_external
      Encoding.default_external = Encoding::US_ASCII

      expect(described_class.each(path).first[:attrs][:name_translations]["pt"]).to eq("Antártica")
    ensure
      Encoding.default_external = external
    end

    it "reads a gzipped file from a path" do
      path = File.join(Dir.mktmpdir, "off.jsonl.gz")
      Zlib::GzipWriter.open(path) { |gz| gz.write(lines) }

      expect(described_class.each(path).count).to eq(2)
    end
  end
end
