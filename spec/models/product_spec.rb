require "rails_helper"

RSpec.describe Product, type: :model do
  let(:product) { Product.make }

  it "expected to be valid" do
    expect(product.errors).to be_empty
    expect(product).to be_valid
  end

  it "expected to be persisted" do
    expect(product.errors).to be_empty
    product.save
    expect(product).to be_persisted
  end

  describe "Validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:code).scoped_to(:org_id) }
  end

  describe "Indexing" do
    it "has a unique index on code per owner, over the rows that have one" do
      index =
        Product.index_specifications.detect do |idx|
          idx.key == { code: 1, org_id: 1 }
        end
      expect(index).to be_present
      expect(index.options[:unique]).to be true
      expect(index.options[:partial_filter_expression]).to eq(code: { "$type" => "string" })
    end
  end

  describe "code" do
    it "files a UPC-A under its EAN-13" do
      product = Product.make(code: "036000291452")
      product.valid?

      expect(product.code).to eq("0036000291452")
    end

    it "leaves a code that is no barcode as it was typed" do
      product = Product.make(code: "HOUSE-7")
      product.valid?

      expect(product.code).to eq("HOUSE-7")
    end

    it "is one product however the barcode is spelled" do
      Product.create!(name: "Cola", code: "0036000291452")

      expect(Product.new(name: "Other cola", code: "036000291452")).not_to be_valid
    end
  end

  describe "#name" do
    it "falls back to a name in any language" do
      product = Product.new(name_translations: { "es" => "Cerveza Quilmes" })

      I18n.with_locale(:pt) { expect(product.name).to eq("Cerveza Quilmes") }
    end
  end

  describe "a code-less product" do
    it "stores no code at all, so two of them fit the unique index" do
      first = Product.create!(name: "Caipirinha", code: "")
      second = Product.create!(name: "Chopp")

      expect(first.reload.attributes).not_to have_key("code")
      expect(second).to be_persisted
    end
  end

  describe "#source" do
    it "is cleared when a person edits what an import wrote" do
      product = Product.create!(name: "Brahma", code: "7891991010023", source: "off")
      product.update!(name: "Brahma Chopp")

      expect(product.reload.source).to be_nil
    end

    it "stays while an importer writes" do
      product = Product.create!(name: "Brahma", code: "7891991010023", source: "off")
      product.importing = true
      product.update!(name: "Brahma Chopp")

      expect(product.reload.source).to eq("off")
    end

    it "stays when only the host's own counters change" do
      product = Product.create!(name: "Brahma", code: "7891991010023", source: "off")
      product.update!(uses: 3)

      expect(product.reload.source).to eq("off")
    end
  end

  describe "#tokens" do
    it "holds the folded words of every name and of the brand" do
      brand = Brand.create!(name: "Ambev")
      product = Product.create!(name_translations: { "pt" => "Cerveja Antártica", "en" => "Antarctica Beer" }, brand: brand)

      expect(product.tokens).to contain_exactly("cerveja", "antartica", "antarctica", "beer", "ambev")
    end
  end

  describe "code per owner" do
    it "lets an org file its own product under a barcode the shared catalogue has" do
      Product.create!(name: "Brahma", code: "7891991010023")
      own = Product.new(name: "Brahma do bar", code: "7891991010023", org_id: BSON::ObjectId.new)

      expect(own).to be_valid
    end
  end

  describe ".lookup" do
    let!(:brahma) { Product.create!(name: "Brahma", code: "7891991010023") }

    it "finds a product by its barcode" do
      expect(Product.lookup("7891991010023")).to eq(brahma)
    end

    it "finds it however the scanner spelled it" do
      expect(Product.lookup(" 7 891991 010023 ")).to eq(brahma)
    end

    it "finds a UPC-A by its EAN-13, and the other way around" do
      cola = Product.create!(name: "Cola", code: "036000291452")

      expect(Product.lookup("036000291452")).to eq(cola)
      expect(Product.lookup("0036000291452")).to eq(cola)
    end

    it "finds a row stored before codes were normalized" do
      old = Product.new(name: "Old cola", code: "036000291452")
      old.collection.insert_one(old.as_document.merge("code" => "036000291452"))

      expect(Product.lookup("0036000291452")).to eq(old)
    end

    it "finds a code that is no barcode as typed" do
      house = Product.create!(name: "House", code: "HOUSE-7")

      expect(Product.lookup("HOUSE-7")).to eq(house)
    end

    it "is nil when the catalogue lacks it" do
      expect(Product.lookup("4006381333931")).to be_nil
      expect(Product.lookup(nil)).to be_nil
    end
  end

  describe "#type_name" do
    it "returns 'Product' for base products" do
      product = Product.new
      expect(product._type).to eq('Product')
    end

    it "returns 'Bebida' for drinks" do
      product = Product.new(_type: 'Drink')
      expect(product.class).to eq(Drink)
    end

    it "returns 'Comida' for food" do
      product = Product.new(_type: 'Food')
      expect(product.class).to eq(Food)
    end
  end

  describe "#type virtual accessor" do
    it "gets and sets the _type field" do
      product = Product.new
      product.type = 'Drink'
      expect(product._type).to eq('Drink')
      expect(product.type).to eq('Drink')
    end
  end

  describe ".search" do
    before do
      Product.create!(name: "Test Beer", brand: Brand.create!(name: "Test Brand", info: "Test"), code: "123456")
      Product.create!(name: "Test Wine", brand: Brand.create!(name: "Wine Brand", info: "Test"), code: "789012")
    end

    it "returns all products when no search term provided" do
      expect(Product.search(nil).count).to eq(2)
      expect(Product.search("").count).to eq(2)
    end

    it "searches by name" do
      expect(Product.search("Beer").count).to eq(1)
    end

    it "searches by brand name" do
      expect(Product.search("Wine Brand").count).to eq(1)
    end

    it "searches by code" do
      expect(Product.search("123456").count).to eq(1)
    end

    it "takes the term as text, not a pattern" do
      expect { Product.search("(").to_a }.not_to raise_error
      expect { Product.search("Test (").to_a }.not_to raise_error
    end

    it "matches the start of every word, accents aside" do
      Product.create!(name: "Cerveja Antártica Original", code: "4006381333931")

      expect(Product.search("antar orig").count).to eq(1)
      expect(Product.search("ANTÁRTICA").count).to eq(1)
      expect(Product.search("ntarti").count).to eq(0) # a prefix, not any substring
    end

    it "finds a name in a language that is not the current one" do
      Product.create!(name_translations: { "es" => "Cerveza Quilmes" }, code: "5901234123457")

      expect(Product.search("quilmes").count).to eq(1)
    end

    it "matches the start of a code" do
      expect(Product.search("1234").count).to eq(1)
    end

    it "is case insensitive" do
      expect(Product.search("beer").count).to eq(1)
      expect(Product.search("BEER").count).to eq(1)
    end
  end
end
