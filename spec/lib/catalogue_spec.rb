require "standalone_helper"
require "support/fake_models"
require "tmpdir"

RSpec.describe Openmarket::Catalogue do
  before { Fake.reset! }

  def importer(**options)
    Openmarket::Importer.new(brands: Fake::Brand, products: Fake::Product, types: Fake::TYPES, **options)
  end

  let(:brahma) do
    Fake::Drink.new(
      code: "7891991010023", name_translations: { "pt" => "Cerveja Brahma", "en" => "Brahma Beer" },
      brand: Fake::Brand.new(name: "Brahma"), kind: :beer, pack: :can, size: 350, acl: 4.8,
      image: "https://images.openfoodfacts.org/b.jpg", quantity: "350 ml",
      countries: %w[ brazil ], tags: %w[ beers ], source: "off"
    )
  end

  describe ".product_record" do
    it "says a drink in the words of the dump" do
      record = described_class.product_record(brahma, { brahma.brand_id => "Brahma" })

      expect(record).to include(
        "type" => "drink", "code" => "7891991010023", "brand" => "Brahma",
        "name" => { "pt" => "Cerveja Brahma", "en" => "Brahma Beer" },
        "kind" => "beer", "pack" => "can", "size" => 350, "acl" => 4.8, "source" => "off"
      )
    end

    it "never carries what is the host's own" do
      record = described_class.product_record(brahma, {})

      expect(record.keys).not_to include("org", "org_id", "sku", "uses", "_id", "id")
    end

    it "says food with its kind and size" do
      food = Fake::Food.new(code: "1", name_translations: { "en" => "Pizza" }, kind: :pizza, size: 400)

      expect(described_class.product_record(food)).to include("type" => "food", "kind" => "pizza", "size" => 400)
    end
  end

  describe ".entry" do
    it "turns a drink record back into an importer entry" do
      record = { "type" => "drink", "code" => "1", "name" => { "pt" => "X" }, "brand" => "B", "kind" => "beer", "acl" => 5.0 }

      expect(described_class.entry(record)).to eq(
        code: "1", brand: "B", type: "Drink",
        attrs: {
          code: "1", name_translations: { "pt" => "X" }, info_translations: nil, image: nil, quantity: nil, source: nil,
          countries: [], tags: [], kind: "beer", pack: nil, size: nil, acl: 5.0
        }
      )
    end

    it "does not let a dump set what it should not" do
      record = { "type" => "drink", "code" => "1", "name" => { "pt" => "X" }, "org_id" => "someone", "sku" => "x", "_id" => "y" }

      expect(described_class.entry(record)[:attrs].keys).not_to include(:org_id, :sku, :_id, :org)
    end

    it "takes a value in the wrong shape for no value" do
      record = { "type" => "drink", "code" => "1", "name" => "Brahma", "countries" => "brazil", "tags" => [ "beers", 7 ],
                 "size" => "350", "acl" => "4.8", "kind" => 5, "image" => [ "x" ] }
      attrs = described_class.entry(record)[:attrs]

      expect(attrs).to include(name_translations: nil, countries: [], tags: [ "beers" ], size: nil, acl: nil, kind: nil, image: nil)
    end

    it "keeps only the names that are text" do
      expect(described_class.translations({ "pt" => "Cerveja", "en" => 5, "es" => " " })).to eq("pt" => "Cerveja")
      expect(described_class.translations([ "Cerveja" ])).to be_nil
    end

    it "takes an unknown type for a plain product" do
      expect(described_class.entry({ "type" => "gadget", "code" => "1" })[:type]).to eq("Product")
    end
  end

  describe "a dump, restored" do
    it "gives back the same catalogue" do
      importer.call([ { code: brahma.code, brand: "Brahma", type: "Drink", attrs: described_class.entry(described_class.product_record(brahma, { brahma.brand_id => "Brahma" }))[:attrs] } ])
      original = Fake::Product.rows.first
      names = Fake::Brand.rows.to_h { |brand| [ original.brand_id, brand.name ] }

      path = File.join(Dir.mktmpdir, "dump.ndjson.gz")
      records = [ described_class.brand_record(original.brand), described_class.product_record(original, names) ]
      Openmarket::Dump.write(path, records)

      Fake.reset!
      stats = described_class.restore(path, brands: Fake::Brand, products: Fake::Product, types: Fake::TYPES)

      expect(stats).to eq(created: 1)
      restored = Fake::Product.rows.first
      expect(restored).to be_a(Fake::Drink)
      expect(restored).to have_attributes(
        code: "7891991010023", name_translations: { "pt" => "Cerveja Brahma", "en" => "Brahma Beer" },
        kind: "beer", pack: "can", size: 350, acl: 4.8, quantity: "350 ml", countries: %w[ brazil ],
        tags: %w[ beers ], source: "off", image: "https://images.openfoodfacts.org/b.jpg"
      )
      expect(restored.brand.name).to eq("Brahma")
    end

    it "counts a malformed row and loads the rest" do
      path = File.join(Dir.mktmpdir, "dump.ndjson")
      Openmarket::Dump.write(path, [
        { "type" => "drink", "code" => "7891991010023", "name" => "a string, not a hash" },
        { "type" => "drink", "code" => "5901234123457", "name" => { "pt" => "Cola" }, "kind" => "soda" },
        { "type" => "drink", "name" => { "pt" => "No code" } }
      ])

      stats = described_class.restore(path, brands: Fake::Brand, products: Fake::Product, types: Fake::TYPES)

      expect(stats).to eq(invalid: 2, created: 1)
      expect(Fake::Product.rows.map(&:code)).to eq(%w[ 5901234123457 ])
    end

    it "keeps what is already there unless told to overwrite" do
      path = File.join(Dir.mktmpdir, "dump.ndjson")
      Openmarket::Dump.write(path, [ { "type" => "drink", "code" => "7891991010023", "name" => { "pt" => "From the dump" }, "kind" => "beer" } ])
      Fake::Drink.new(code: "7891991010023", name_translations: { "pt" => "Mine" }).save

      kept = described_class.restore(path, brands: Fake::Brand, products: Fake::Product, types: Fake::TYPES)
      expect(kept).to eq(kept: 1)
      expect(Fake::Product.rows.first.name).to eq("Mine")

      over = described_class.restore(path, overwrite: true, brands: Fake::Brand, products: Fake::Product, types: Fake::TYPES)
      expect(over).to eq(updated: 1)
      expect(Fake::Product.rows.first.name).to eq("From the dump")
    end
  end
end
