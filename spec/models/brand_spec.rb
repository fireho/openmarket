require "rails_helper"

RSpec.describe Brand, type: :model do
  it "is valid with a name alone" do
    expect(Brand.new(name: "Brahma")).to be_valid
  end

  describe "Validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name) }
    it { is_expected.not_to validate_presence_of(:info) }
  end

  describe "#key" do
    it "is the name folded" do
      brand = Brand.new(name: "Antártica ")
      brand.valid?

      expect(brand.key).to eq("antartica")
    end

    it "is taken when another spelling of the name is" do
      Brand.create!(name: "Antártica")

      expect(Brand.new(name: "ANTARTICA")).not_to be_valid
    end
  end

  describe ".named" do
    let!(:brand) { Brand.create!(name: "Antártica") }

    it "finds a brand however it was cased or accented" do
      expect(Brand.named("antartica")).to eq(brand)
      expect(Brand.named(" ANTÁRTICA ")).to eq(brand)
    end

    it "finds a brand made before keys existed, by its exact name" do
      old = Brand.new(name: "Skol")
      old.collection.insert_one(old.as_document.except("key"))

      expect(Brand.named("Skol")).to eq(old)
    end

    it "is nil for a stranger, or for nothing" do
      expect(Brand.named("Brahma")).to be_nil
      expect(Brand.named("")).to be_nil
    end
  end

  describe ".search" do
    before do
      Brand.create!(name: "Brahma")
      Brand.create!(name: "ambev")
      Brand.create!(name: "Antártica")
    end

    it "finds the brands a name starts with, accents and case aside" do
      expect(Brand.search("ANTAR").map(&:name)).to eq([ "Antártica" ])
      expect(Brand.search("rahma").to_a).to be_empty # a prefix, not any substring
    end

    it "is every brand, in the order people read names, when nothing is typed" do
      expect(Brand.search(nil).map(&:name)).to eq(%w[ ambev Antártica Brahma ])
      expect(Brand.search(" ").count).to eq(3)
    end

    it "takes the term as text, not a pattern" do
      expect { Brand.search("(").to_a }.not_to raise_error
      expect(Brand.search(".*").to_a).to be_empty
    end
  end

  describe "what a form sends" do
    it "stores nothing for a field left blank" do
      brand = Brand.create!(name: "Brahma", wikidata: "", site: " ")

      expect(Brand.where(wikidata: nil, site: nil)).to include(brand)
      expect(brand.reload.wikidata).to be_nil
    end

    it "writes the country as ISO does" do
      expect(Brand.create!(name: "Brahma", country: "br").country).to eq("BR")
    end
  end

  describe "#destroy" do
    it "is refused while products are filed under the brand" do
      brand = Brand.create!(name: "Brahma")
      Product.create!(name: "Brahma Chopp", brand: brand)

      expect(brand.destroy).to be false
      expect(brand.errors[:products]).to be_present
      expect(Brand.where(_id: brand.id)).to exist
    end

    it "goes ahead for a brand with no products" do
      brand = Brand.create!(name: "Brahma")

      expect(brand.destroy).to be true
      expect(Brand.where(_id: brand.id)).not_to exist
    end
  end
end
