require "standalone_helper"
require "support/fake_models"

RSpec.describe Openmarket::Importer do
  before { Fake.reset! }

  let(:importer) { described_class.new(brands: Fake::Brand, products: Fake::Product, types: Fake::TYPES) }

  def entry(code: "7891991010023", brand: "Brahma", name: "Cerveja Brahma", **attrs)
    {
      code: code, brand: brand, type: "Drink",
      attrs: { code: code, name_translations: { "pt" => name }, kind: :beer, source: "off" }.merge(attrs)
    }
  end

  it "creates a drink, with its brand" do
    importer.call([ entry ])

    expect(importer.stats).to eq(created: 1)
    drink = Fake::Product.rows.first
    expect(drink).to be_a(Fake::Drink)
    expect(drink.code).to eq("7891991010023")
    expect(drink.brand.name).to eq("Brahma")
  end

  it "makes one brand of a name however it is cased or accented" do
    importer.call([ entry(code: "1", brand: "Antártica"), entry(code: "2", brand: "ANTARTICA "), entry(code: "3", brand: "antartica") ])

    expect(Fake::Brand.rows.map(&:name)).to eq([ "Antártica" ])
    expect(Fake::Product.rows.map(&:brand).uniq.size).to eq(1)
  end

  it "takes a product without a brand" do
    importer.call([ entry(brand: nil) ])

    expect(importer.stats).to eq(created: 1)
    expect(Fake::Product.rows.first.brand).to be_nil
  end

  it "refreshes a row an earlier import wrote" do
    importer.call([ entry(name: "Cerveja Brahma") ])
    importer.call([ entry(name: "Brahma Chopp") ])

    expect(Fake::Product.rows.size).to eq(1)
    expect(Fake::Product.rows.first.name).to eq("Brahma Chopp")
    expect(importer.stats).to eq(created: 1, updated: 1)
  end

  it "leaves alone a row someone corrected by hand" do
    importer.call([ entry(name: "Cerveja Brahma", source: nil) ])
    importer.call([ entry(name: "Wrong, from the import") ])

    expect(Fake::Product.rows.first.name).to eq("Cerveja Brahma")
    expect(importer.stats).to eq(created: 1, kept: 1)
  end

  it "leaves alone a row of another type" do
    Fake::Product.new(code: "7891991010023", name_translations: { "pt" => "House blend" }, source: "off").save
    importer.call([ entry ])

    expect(Fake::Product.rows.first.name).to eq("House blend")
    expect(importer.stats).to eq(kept: 1)
  end

  it "counts a bad row and goes on" do
    importer.call([ entry(code: "1", name: ""), entry(code: "2") ])

    expect(importer.stats).to eq(invalid: 1, created: 1)
    expect(importer.errors).to eq([ "1: Name can't be blank" ])
  end

  it "takes a blank brand for no brand" do
    importer.call([ entry(brand: "   ") ])

    expect(importer.stats).to eq(created: 1)
    expect(Fake::Product.rows.first.brand).to be_nil
  end

  it "does not stop for a brand that will not save" do
    allow_any_instance_of(Fake::Brand).to receive(:save).and_return(false)
    importer.call([ entry(brand: "Brahma") ])

    expect(importer.stats).to eq(created: 1, brand_invalid: 1)
    expect(Fake::Product.rows.first.brand).to be_nil
  end

  it "does not stop for a row that raises" do
    allow(Fake::Drink).to receive(:new).and_call_original
    allow(Fake::Drink).to receive(:new).with(hash_including(code: "4006381333931")).and_raise(TypeError, "bad value")
    importer.call([ entry(code: "4006381333931"), entry(code: "5901234123457") ])

    expect(importer.stats).to eq(invalid: 1, created: 1)
    expect(importer.errors).to eq([ "4006381333931: TypeError: bad value" ])
  end

  it "refuses a row with no code instead of matching a codeless product" do
    Fake::Product.new(name_translations: { "pt" => "Chopp da casa" }).save
    importer.call([ entry(code: nil), entry(code: "  ") ])

    expect(importer.stats).to eq(invalid: 2)
    expect(Fake::Product.rows.map(&:name)).to eq([ "Chopp da casa" ])
  end

  it "files the code in its canonical spelling" do
    importer.call([ entry(code: "036000291452") ])

    expect(Fake::Product.rows.first.code).to eq("0036000291452")
  end

  it "finds a row stored under another spelling of its barcode" do
    old = Fake::Drink.new(code: "036000291452", name_translations: { "pt" => "Old" }, source: "off")
    Fake::Product.rows << old # saved before codes were normalised
    importer.call([ entry(code: "0036000291452", name: "New") ])

    expect(importer.stats).to eq(updated: 1)
    expect(Fake::Product.rows).to eq([ old ])
    expect(old.name).to eq("New")
  end

  it "is not blocked by an org's own product with the same barcode" do
    Fake::Drink.new(code: "7891991010023", org_id: "bar-42", name_translations: { "pt" => "Brahma do bar" }).save
    importer.call([ entry ])

    expect(importer.stats).to eq(created: 1)
    expect(Fake::Product.shared.rows.map(&:name)).to eq([ "Cerveja Brahma" ])
    expect(Fake::Product.rows.find(&:org_id).name).to eq("Brahma do bar")
  end

  it "marks its own saves as imports, so they do not count as a person's edit" do
    importer.call([ entry ])

    expect(Fake::Product.rows.first.importing).to be true
  end

  it "finds a brand made before keys existed by its name" do
    legacy = Fake::Brand.legacy("Brahma")
    importer.call([ entry(brand: "Brahma") ])

    expect(Fake::Brand.rows).to eq([ legacy ])
    expect(Fake::Product.rows.first.brand).to equal(legacy)
  end

  it "says how far it is" do
    heard = []
    counted = described_class.new(brands: Fake::Brand, products: Fake::Product, types: Fake::TYPES,
                                  every: 2, progress: ->(stats) { heard << stats.values.sum })
    counted.call((1..5).map { |n| entry(code: n.to_s) })

    expect(heard).to eq([ 2, 4 ])
  end

  it "can be told to overwrite everything" do
    importer.call([ entry(name: "Cerveja Brahma", source: nil) ])
    overwriting = described_class.new(refresh: ->(_) { true }, brands: Fake::Brand, products: Fake::Product, types: Fake::TYPES)
    overwriting.call([ entry(name: "Brahma Chopp") ])

    expect(Fake::Product.rows.first.name).to eq("Brahma Chopp")
  end

  describe "#brand" do
    it "starts a new brand with what it is given" do
      brand = importer.brand("Ambev", info: "Brewer", country: "BR")

      expect(brand).to have_attributes(name: "Ambev", info: "Brewer", country: "BR")
    end

    it "leaves an existing brand as it is" do
      importer.brand("Ambev", country: "BR")
      importer.brand("Ambev", country: "XX")

      expect(Fake::Brand.named("Ambev").country).to eq("BR")
    end

    it "rewrites an existing brand when asked" do
      importer.brand("Ambev", country: "BR")
      importer.brand("Ambev", update: true, country: "XX")

      expect(Fake::Brand.named("Ambev").country).to eq("XX")
    end
  end
end
