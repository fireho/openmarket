require "rails_helper"

RSpec.describe Food, type: :model do
  let(:food) { Food.make }

  it "expected to be valid" do
    expect(food.errors).to be_empty
    expect(food).to be_valid
  end

  it "expected to be persisted" do
    expect(food.errors).to be_empty
    food.save
    expect(food).to be_persisted
  end

  it "should have correct type" do
    expect(food.class).to eq(Food)
  end

  describe "Validations" do
    it { is_expected.to validate_presence_of(:name) }
    it do
      is_expected.to validate_inclusion_of(:kind).to_allow(Food.kinds.keys)
    end
    it do
      is_expected.to validate_inclusion_of(:pack).to_allow(Food.packs.keys)
    end
    it do
      is_expected.to validate_numericality_of(:size).to_allow(
        only_integer: true,
        greater_than: 0
      )
    end
  end

  describe "#kind" do
    it "should have new nice enumere and not interfere with field string" do
      food = Food.make(size: 500, kind: "snack")
      expect(food.kind).to eq(:snack)
    end

    it "should have new nice enumere and not interfere with field symbol" do
      food = Food.make(size: 500, kind: :snack)
      expect(food.kind).to eq(:snack)
    end

    it "should have an easy accessor for keys" do
      expect(Food.kinds).to include(:fast, :burger, :pizza, :snack)
    end

    it "should have data for each kind" do
      expect(Food.kinds[:snack]).to be_present
    end

    it "should provide select options" do
      I18n.locale = :pt # Ensure locale is set for this test
      expect(Food.kinds_select).to include(["Lanche Rápido", :fast])
      I18n.locale = I18n.default_locale # Reset locale
    end

    it "should list all defined kinds" do
      expect(Food.kinds).to include(:fast, :burger, :pizza, :pasta, :sushi, :dessert, :snack, :meat)
    end
  end

  describe "#size_g" do
    it "returns the size with g suffix" do
      food = Food.make(size: 500)
      expect(food.size_g).to eq("500g")
    end

    it "returns nil when size is not set" do
      food = Food.make(size: nil)
      expect(food.size_g).to be_nil
    end
  end

  describe "icon" do
    it "should have an icon" do
      expect(Food.icon).to be_present
    end
  end
end
