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
end
