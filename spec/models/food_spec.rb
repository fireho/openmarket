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
      is_expected.to validate_numericality_of(:size).to_allow(
        only_integer: true,
        greater_than: 0
      )
    end

    # A form sends "" for an empty field, not nil.
    it "takes a blank size from the form" do
      expect(Food.make(size: "")).to be_valid
    end

    it "still refuses a size that is not a number" do
      expect(Food.make(size: "prato")).not_to be_valid
    end
  end

  # Enumere's contract: the field is a String and the
  # members are keyed by string, so a symbol written in reads back a string.
  describe "#kind" do
    it "reads a member written as a string" do
      expect(Food.make(size: 500, kind: "snack").kind).to eq("snack")
    end

    it "reads a member written as a symbol as its string" do
      expect(Food.make(size: 500, kind: :snack).kind).to eq("snack")
    end

    it "is fast food when nobody says" do
      expect(Food.new.kind).to eq("fast")
    end

    it "offers the kinds to a select, named in the reader's language" do
      I18n.locale = :pt
      expect(Food.kinds_select).to include([ "Lanche Rápido", "fast" ])
    end

    it "lists every kind" do
      expect(Food.kinds.keys).to include(*%w[ fast burger pizza pasta sushi dessert snack meat ])
    end

    it "has a name for every kind, in en and pt" do
      %i[ en pt ].each do |locale|
        Food.kinds.each_key { |key| expect(I18n.exists?("mongoid.attributes.food.kind_enums.#{key}", locale)).to be(true), "#{locale}: #{key}" }
      end
    end

    # Food comes on a plate, not in a can: no packs, so the form asks none.
    it "has no pack" do
      expect(Food.new).not_to respond_to(:pack)
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
