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
    it { is_expected.to validate_uniqueness_of(:code).scoped_to(:org_id) }
    it do
      is_expected.to validate_inclusion_of(:kind).to_allow(Drink.kinds.keys)
    end
    it do
      is_expected.to validate_inclusion_of(:pack).to_allow(Drink.packs.keys)
    end
    it do
      is_expected.to validate_numericality_of(:acl).to_allow(
        greater_than_or_equal_to: 0,
        less_than_or_equal_to: 100
      )
    end
    it do
      is_expected.to validate_numericality_of(:size).to_allow(
        only_integer: true,
        greater_than: 0
      )
    end

    # A form sends "" for an empty field, not nil — a recipe has no bottle.
    it "takes a blank size from the form" do
      expect(Drink.make(size: "", acl: 5)).to be_valid
    end

    it "still refuses a size that is not a number" do
      drink = Drink.make(size: "garrafa", acl: 5)

      expect(drink).not_to be_valid
      expect(drink.errors[:size]).to be_present
    end
  end

  describe "Indexing" do
    it "has a unique index on code per owner, over the rows that have one" do
      index =
        Drink.index_specifications.detect do |idx|
          idx.key == { code: 1, org_id: 1 }
        end
      expect(index).to be_present
      expect(index.options[:unique]).to be true
      expect(index.options[:partial_filter_expression]).to eq(code: { "$type" => "string" })
    end
  end

  # Enumere's contract, as fire writes it: the field is a String and the
  # members are keyed by string, so a symbol written in reads back a string.
  describe "#kind" do
    it "reads a member written as a string" do
      expect(Drink.make(kind: "beer").kind).to eq("beer")
    end

    it "reads a member written as a symbol as its string" do
      expect(Drink.make(kind: :beer).kind).to eq("beer")
    end

    it "is a beer in a can when nobody says" do
      expect(Drink.new).to have_attributes(kind: "beer", pack: "can")
    end

    it "carries what each kind declares" do
      expect(Drink.kinds["beer"][:acl]).to eq(5)
      expect(Drink.new(kind: "whisky").kind_data[:acl]).to eq(40)
    end

    it "offers the kinds to a select, named in the reader's language" do
      I18n.locale = :pt
      expect(Drink.kinds_select).to include([ "Cerveja", "beer" ])
    end

    it "names the kind and the pack" do
      I18n.locale = :pt
      expect(Drink.new(kind: "wine", pack: "can")).to have_attributes(kind_name: "Vinho", pack_name: "Lata")
    end

    it "lists every kind the catalogue files drinks under" do
      expect(Drink.kinds.keys).to include(*%w[ beer water whisky gin rum cachaca wine vodka cognac cider liquor tequila soda juice energy mixed tea ])
    end

    it "has a name for every kind and pack, in en and pt" do
      %i[ en pt ].each do |locale|
        Drink.kinds.each_key { |key| expect(I18n.exists?("mongoid.attributes.drink.kind_enums.#{key}", locale)).to be(true), "#{locale}: #{key}" }
        Drink.packs.each_key { |key| expect(I18n.exists?("mongoid.attributes.drink.pack_enums.#{key}", locale)).to be(true), "#{locale}: #{key}" }
      end
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

  describe "#acl" do
    it "keeps the decimals" do
      expect(Drink.make(acl: "7.6%").acl).to eq(7.6)
      expect(Drink.make(acl: "4,8").acl).to eq(4.8)
      expect(Drink.make(acl: 40).acl).to eq(40.0)
    end

    it "is a float" do
      expect(Drink.make(acl: 5).acl).to be_a(Float)
    end

    it "is unknown, not zero, when blank" do
      drink = Drink.make(size: 350, acl: "")

      expect(drink.acl).to be_nil
      expect(drink).to be_valid
      expect(drink.alcohol).to be_nil
    end

    it "prints the decimals, but not a needless .0" do
      expect(Drink.make(acl: 4.8).alcohol).to eq("4.8%")
      expect(Drink.make(acl: 40).alcohol).to eq("40%")
    end

    it "refuses more than 100" do
      expect(Drink.make(acl: 140)).not_to be_valid
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

    it "returns 0 for a recipe with no bottle" do
      expect(Drink.make(size: nil, acl: 5).acl_price(1000)).to eq(0)
    end

    it "returns 0 if alcohol is unknown" do
      expect(Drink.make(size: 350, acl: nil).acl_price(1000)).to eq(0)
    end

    it "returns 0 if alcohol is zero" do
      allow(drink).to receive(:acl).and_return(0)
      expect(drink.acl_price(1000)).to eq(0)
    end
  end

end
