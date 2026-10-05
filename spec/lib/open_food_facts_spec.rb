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

      it "ignores nonsense" do
        row = brahma.merge("nutriments" => { "alcohol_100g" => 480 })
        expect(described_class.map(row)[:attrs][:acl]).to be_nil
      end
    end

    describe "kind" do
      def kind_of(*tags)
        described_class.map(brahma.merge("categories_tags" => [ "en:beverages", *tags ]))&.dig(:attrs, :kind)
      end

      it "picks the narrow before the wide" do
        expect(kind_of("en:alcoholic-beverages", "en:spirits", "en:gins")).to eq(:gin)
        expect(kind_of("en:carbonated-drinks", "en:sodas", "en:energy-drinks")).to eq(:energy)
      end

      it "knows the kinds a bar sells" do
        expect(kind_of("en:wines")).to eq(:wine)
        expect(kind_of("en:cachacas")).to eq(:cachaca)
        expect(kind_of("en:waters", "en:mineral-waters")).to eq(:water)
        expect(kind_of("en:fruit-juices")).to eq(:juice)
        expect(kind_of("en:ciders")).to eq(:cider)
      end
    end

    describe "pack" do
      def pack_of(row) = described_class.map(brahma.merge(row))[:attrs][:pack]

      it { expect(pack_of("packaging_tags" => %w[ en:bottle en:glass ])).to eq(:grf) }
      it { expect(pack_of("packaging_tags" => %w[ en:bottle en:plastic-bottle ])).to eq(:pet) }
      it { expect(pack_of("packaging_tags" => %w[ en:bottle ])).to eq(:grf) }
      it { expect(pack_of("quantity" => "6 x 350 ml")).to eq(:kit) }

      it "reads the name when the tags say nothing" do
        expect(pack_of("packaging_tags" => [], "product_name" => "Cerveja Amstel Lata", "lang" => "pt")).to eq(:can)
      end

      it "is nil, not a guess, when nothing says" do
        expect(pack_of("packaging_tags" => [], "product_name" => "Cerveja X")).to be_nil
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

    it "reads a gzipped file from a path" do
      path = File.join(Dir.mktmpdir, "off.jsonl.gz")
      Zlib::GzipWriter.open(path) { |gz| gz.write(lines) }

      expect(described_class.each(path).count).to eq(2)
    end
  end
end
