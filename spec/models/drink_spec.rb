require "rails_helper"

RSpec.describe Drink, type: :model do
  let(:drink) { Drink.make }

  it "expected to be valid" do
    expect(drink.errors).to be_empty
    expect(drink).to be_valid
  end

  it "expected to be persisted" do
    expect(drink.errors).to be_empty
    drink.save
    expect(drink).to be_persisted
  end

  it "should have correct type" do
    expect(drink.class).to eq(Drink)
    expect(drink.drink?).to be true
    expect(drink.food?).to be false
  end

  describe "Validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:code) }
    it do
      is_expected.to validate_inclusion_of(:kind).to_allow(Drink.kinds.keys)
    end
    it do
      is_expected.to validate_inclusion_of(:pack).to_allow(Drink.packs.keys)
    end
    it do
      is_expected.to validate_numericality_of(:acl).to_allow(
        only_integer: true,
        greater_than_or_equal_to: 0
      )
    end
    it do
      is_expected.to validate_numericality_of(:size).to_allow(
        only_integer: true,
        greater_than: 0
      )
    end
  end

  describe "Indexing" do
    it "has a sparsed index on code" do
      index =
        Drink.index_specifications.detect do |idx|
          idx.key == { code: 1 }
        end
      expect(index).to be_present
      expect(index.options[:unique]).to be true
      expect(index.options[:sparse]).to be true
    end
  end

  describe "#kind" do
    it "should have new nice enumere and not interfere with field string" do
      drink = Drink.make(size: 750, acl: 40, kind: "beer")
      expect(drink.kind).to eq(:beer)
    end

    it "should have new nice enumere and not interfere with field symbol" do
      drink = Drink.make(size: 750, acl: 40, kind: :beer)
      expect(drink.kind).to eq(:beer)
    end

    it "should have an easy accessor for keys" do
      expect(Drink.kinds).to include(:beer, :wine, :vodka)
    end

    it "should have data for each kind" do
      expect(Drink.kinds[:beer]).to be_present
      expect(Drink.kinds[:beer][:acl]).to eq(5) # Assuming this is the acl for beer
    end

    it "should provide select options" do
      I18n.locale = :pt # Ensure locale is set for this test
      expect(Drink.kinds_select).to include(["Cerveja", :beer])
      I18n.locale = I18n.default_locale # Reset locale
    end

    it "should have translations for kind" do
      I18n.locale = :pt
      drink = Drink.new(kind: "beer")
      expect(drink.kind_name).to eq("Cerveja") # Or whatever the PT translation is
    end

    it "should have translations for kind" do
      I18n.locale = :pt
      drink = Drink.new(kind: "wine")
      expect(drink.kind_name).to eq("Vinho") # Or whatever the PT translation is
    end

    it "should have translations for pack" do
      I18n.locale = :pt
      drink = Drink.new(pack: "can")
      expect(drink.pack_name).to eq("Lata") # Or whatever the PT translation is
    end

    it "should list all defined kinds" do
      expect(Drink.kinds).to include(:rum, :gin, :beer, :wine, :vodka, :whisky, :tequila, :soda, :water, :juice, :energy, :cognac, :liquor)
    end

    it "should provide translated data for all kinds" do
      I18n.locale = :pt
      # Example check, assuming 'Cerveja' is the PT translation for beer
      expect(Drink.kinds[:beer][:name]).to eq("Cerveja")
      expect(Drink.kinds[:wine][:name]).to eq("Vinho") # Assuming 'Vinho' for wine
    end
  end

  describe "#alcohol" do
    it "returns the alcohol content with a percent sign" do
      drink = Drink.make(size: 750, acl: 40)
      expect(drink.alcohol).to eq("40%")
    end

    it "parses only the number" do
      drink = Drink.make(size: 750, acl: "30%")
      expect(drink.alcohol).to eq("30%")
    end
  end

  describe "#size_ml" do
    it "returns the size with ml suffix" do
      drink = Drink.make(size: 750)
      expect(drink.size_ml).to eq("750ml")
    end
  end

  describe "#acl_price" do
    let(:drink) { Drink.make(size: 1000, acl: 50) }

    it "calculates the price per milliliter of pure alcohol" do
      price = 10_000 # $100.00
      expect(drink.acl_price(price)).to eq(20.0) # $0.20 per ml
    end

    it "returns 0 if size is zero" do
      allow(drink).to receive(:size).and_return(0)
      expect(drink.acl_price(1000)).to eq(0)
    end

    it "returns 0 if alcohol is zero" do
      allow(drink).to receive(:acl).and_return(0)
      expect(drink.acl_price(1000)).to eq(0)
    end
  end

end
