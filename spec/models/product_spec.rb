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

    # Mongoid fills a field's default into a row stored without it, and
    # reports that as a change: "beer" for a drink's kind. Not an edit.
    it "stays on a row stored without its defaults" do
      Product.collection.insert_one(_type: "Drink", name: { "en" => "Brahma" }, code: "7891991010023", source: "off")
      drink = Product.find_by(code: "7891991010023")
      drink.update!(uses: 3)

      expect(drink.reload.source).to eq("off")
    end
  end

  describe "#tokens" do
    it "holds the folded words of every name and of the brand" do
      brand = Brand.create!(name: "Ambev")
      product = Product.create!(name_translations: { "pt" => "Cerveja Antártica", "en" => "Antarctica Beer" }, brand: brand)

      expect(product.tokens).to contain_exactly("cerveja", "antartica", "antarctica", "beer", "ambev")
    end
  end

  describe "#brand_name" do
    it "is the brand's name" do
      expect(Product.new(brand: Brand.new(name: "Brahma")).brand_name).to eq("Brahma")
      expect(Product.new.brand_name).to be_nil
    end

    it "finds the brand however it was typed" do
      brand = Brand.create!(name: "Antártica")

      expect { Product.new(brand_name: " ANTARTICA ") }.not_to change(Brand, :count)
      expect(Product.new(brand_name: " ANTARTICA ").brand).to eq(brand)
    end

    it "makes a brand nobody has yet" do
      product = nil
      expect { product = Product.new(brand_name: "Cervejaria  Nova ") }.to change(Brand, :count).by(1)

      expect(product.brand).to be_persisted
      expect(product.brand.name).to eq("Cervejaria Nova")
    end

    it "takes the brand off when blank" do
      product = Product.create!(name: "Chopp", brand: Brand.create!(name: "Brahma"))
      product.update!(brand_name: " ")

      expect(product.reload.brand).to be_nil
    end

    it "finds the brand behind what a paste brings along: a BOM, a zero-width space" do
      brand = Brand.create!(name: "Brahma")

      expect { Product.new(brand_name: "\uFEFFBrahma\u200B") }.not_to change(Brand, :count)
      expect(Product.new(brand_name: "Brahma\u200B").brand).to eq(brand)
      expect(Product.new(brand_name: "\u200B").brand).to be_nil # nothing a brand could be named
    end

    it "finds a new brand pasted with a BOM the second time" do
      first = Product.new(brand_name: "\uFEFFCervejaria Nova").brand

      expect { Product.new(brand_name: "\uFEFFCervejaria Nova") }.not_to change(Brand, :count)
      expect(Product.new(brand_name: "\uFEFFCervejaria Nova").brand).to eq(first)
      expect(first.name).to eq("Cervejaria Nova")
    end

    context "when someone saves the same new brand a moment before" do
      let!(:theirs) { Brand.create!(name: "Cervejaria Nova") }

      before do # the look comes before theirs is saved
        looks = 0
        allow(Brand).to receive(:named).and_wrap_original { |named, name| (looks += 1) == 1 ? nil : named.call(name) }
      end

      it "takes theirs when the uniqueness check refuses the second" do
        expect(Product.new(brand_name: "Cervejaria Nova").brand).to eq(theirs)
      end

      it "takes theirs when the unique index refuses it" do
        allow(Brand).to receive(:create!).and_raise(Mongo::Error::OperationFailure, "E11000 duplicate key error")

        expect(Product.new(brand_name: "Cervejaria Nova").brand).to eq(theirs)
      end
    end

    it "raises a refusal that no saved brand explains" do
      allow(Brand).to receive(:create!).and_raise(Mongo::Error::OperationFailure, "not primary")

      expect { Product.new(brand_name: "Cervejaria Nova") }.to raise_error(Mongo::Error::OperationFailure)
    end

    it "is an edit like any other, so an import leaves the row alone" do
      imported = Product.new(name: "Brahma", code: "7891991010023", source: "off")
      imported.importing = true
      imported.save!

      product = Product.find(imported.id) # as a person's form loads it
      expect(product.source).to eq("off")
      product.update!(brand_name: "Ambev")

      expect(product.reload.source).to be_nil
      expect(product.tokens).to include("ambev")
    end
  end

  describe "code per owner" do
    it "lets an org file its own product under a barcode the shared catalogue has" do
      Product.create!(name: "Brahma", code: "7891991010023")
      own = Product.new(name: "Brahma do bar", code: "7891991010023", org_id: BSON::ObjectId.new)

      expect(own).to be_valid
    end
  end

  describe "#brand_name=" do
    it "keeps a product on the spelling it has, saved again" do
      legacy = Brand.new(name: "ANTARTICA")
      legacy.collection.insert_one(legacy.as_document.except("key")) # no key: a spelling waiting to be merged
      Brand.create!(name: "Antártica")
      product = Drink.create!(name: "Guaraná", brand: legacy, source: "off")

      product.update!(brand_name: "ANTARTICA")
      expect(product.reload.brand).to eq(legacy)
      expect(product.source).to eq("off")
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
    it "names the class in the reader's language" do
      I18n.locale = :pt
      expect([ Drink.new, Food.new, Product.new ].map(&:type_name)).to eq(%w[ Bebida Comida Produto ])
    end
  end

  describe "#type" do
    it "is the class, as the form's radio names it" do
      expect([ Drink.new, Food.new, Product.new ].map(&:type)).to eq(%w[ Drink Food Product ])
    end

    it "is never assigned: the class is picked at new" do
      expect(Product.new).not_to respond_to(:type=)
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
  describe ".parse" do
    it "reads a menu line into an unsaved drink" do
      drink = Product.parse("Cerveja Patagonia LATA 350ml  R$ 12,90")

      expect(drink).to be_a(Drink)
      expect(drink).to be_new_record
      expect(drink).to have_attributes(name: "Cerveja Patagonia", size: 350)
      expect(drink.kind.to_s).to eq("beer")
      expect(drink.pack.to_s).to eq("can")
    end

    it "reads food by its weight" do
      expect(Product.parse("Porção de batata frita 400g")).to be_a(Food)
    end

    it "leaves what the line does not say nil, never the model's default" do
      drink = Product.parse("Heineken LN 330")
      expect(drink.kind).to be_nil
      expect(Product.parse("Can Blau 750ml").pack).to be_nil
    end

    it "is nil for a line that says neither" do
      expect(Product.parse("Café 500g")).to be_nil
      expect(Product.parse("")).to be_nil
    end
  end

  describe ".match" do
    let!(:brahma) { Drink.create!(name: "Cerveja Brahma Chopp", code: "7891991010023", size: 350) }

    it "finds the catalogue's product by the barcode on the line" do
      expect(Product.match("Brahma lata 7891991010023")).to eq(brahma)
    end

    it "finds it by its words and size" do
      expect(Product.match("Brahma Chopp 350ml")).to eq(brahma)
    end

    it "does not take another size for it" do
      expect(Product.match("Brahma Chopp 600ml")).to be_nil
    end

    it "takes the one with the fewest words the line did not say" do
      cola = Drink.create!(name: "Coca-Cola", code: "5449000000996", size: 350)
      Drink.create!(name: "Coca-Cola Zero", code: "5449000131805", size: 350)

      expect(Product.match("Coca-Cola lata 350ml")).to eq(cola)
    end

    it "is nil when two fit as well: the bar picks" do
      Drink.create!(name: "Cerveja Brahma Zero", code: "4006381333931", size: 600)
      Drink.create!(name: "Cerveja Brahma Duplo", code: "5901234123457", size: 600)

      expect(Product.match("Cerveja Brahma 600ml")).to be_nil # Zero or Duplo: the line does not say
      expect(Product.match("Brahma Zero 600ml").name).to eq("Cerveja Brahma Zero")
    end

    it "takes a kind word in the name for no extra word: a plain Brahma is the Chopp" do
      Drink.create!(name: "Cerveja Brahma Zero", code: "4006381333931", size: 350)

      expect(Product.match("Brahma 350ml")).to eq(brahma)
    end

    it "finds the catalogue's product without the menu's kind word" do
      heineken = Drink.create!(name: "Heineken", code: "8712000900045", size: 330)

      expect(Product.match("Cerveja Heineken Long Neck 330ml")).to eq(heineken)
    end

    it "does not take a case for a can" do
      Drink.create!(name: "Guaraná Antarctica", code: "7891991000833", size: 350, pack: :kit)

      expect(Product.match("Guaraná Antarctica lata 350ml")).to be_nil
    end
  end
end
