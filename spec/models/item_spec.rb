require "rails_helper"

RSpec.describe Item, type: :model do
  let(:item) { Item.make }

  it "expected to be valid" do
    expect(item.errors).to be_empty
    expect(item).to be_valid
  end

  it "expected to be persisted" do
    expect(item.errors).to be_empty
    item.save
    expect(item).to be_persisted
  end

  describe "Validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:code) }
  end

  describe "Indexing" do
    it "has a sparsed index on code" do
      index =
        Item.index_specifications.detect do |idx|
          idx.key == { code: 1 }
        end
      expect(index).to be_present
      expect(index.options[:unique]).to be true
      expect(index.options[:sparse]).to be true
    end
  end

  describe "#type_name" do
    it "returns 'Item' for base items" do
      item = Item.new
      expect(item._type).to eq('Item')
    end

    it "returns 'Bebida' for drinks" do
      item = Item.new(_type: 'Drink')
      expect(item.class).to eq(Drink)
    end

    it "returns 'Comida' for food" do
      item = Item.new(_type: 'Food')
      expect(item.class).to eq(Food)
    end
  end

  describe "#type virtual accessor" do
    it "gets and sets the _type field" do
      item = Item.new
      item.type = 'Drink'
      expect(item._type).to eq('Drink')
      expect(item.type).to eq('Drink')
    end
  end

  describe ".search" do
    before do
      Item.create!(name: "Test Beer", brand: Brand.create!(name: "Test Brand", info: "Test"), code: "123456")
      Item.create!(name: "Test Wine", brand: Brand.create!(name: "Wine Brand", info: "Test"), code: "789012")
    end

    it "returns all items when no search term provided" do
      expect(Item.search(nil).count).to eq(2)
      expect(Item.search("").count).to eq(2)
    end

    it "searches by name" do
      expect(Item.search("Beer").count).to eq(1)
    end

    it "searches by brand name" do
      expect(Item.search("Wine Brand").count).to eq(1)
    end

    it "searches by code" do
      expect(Item.search("123456").count).to eq(1)
    end

    it "is case insensitive" do
      expect(Item.search("beer").count).to eq(1)
      expect(Item.search("BEER").count).to eq(1)
    end
  end
end
