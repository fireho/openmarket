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
    it { is_expected.to validate_uniqueness_of(:code) }
  end

  describe "Indexing" do
    it "has a sparsed index on code" do
      index =
        Product.index_specifications.detect do |idx|
          idx.key == { code: 1 }
        end
      expect(index).to be_present
      expect(index.options[:unique]).to be true
      expect(index.options[:sparse]).to be true
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

    it "is case insensitive" do
      expect(Product.search("beer").count).to eq(1)
      expect(Product.search("BEER").count).to eq(1)
    end
  end
end
