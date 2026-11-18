require "rails_helper"
require "tmpdir"

RSpec.describe Brand, type: :model do
  it "is valid with a name alone" do
    expect(Brand.new(name: "Brahma")).to be_valid
  end

  describe "Validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:org_id) }
    it { is_expected.to validate_uniqueness_of(:key).scoped_to(:org_id) }
    it { is_expected.not_to validate_presence_of(:info) }
  end

  describe "indexes" do
    # The index names a plan walks, the winner's or every candidate's.
    def scans(plan)
      case plan
      when Hash then [ plan["indexName"], *plan.values.flat_map { scans(it) } ].compact
      when Array then plan.flat_map { scans(it) }
      else []
      end
    end

    # In the house shape, `$gt ""`: an equality on key implies it, so the
    # planner may take the index. `$type` is implied by nothing but itself.
    it "has the key unique per owner, only where there is a key, and reads a key on it" do
      index = Brand.index_specifications.find { |spec| spec.key.to_a == [ [ :key, 1 ], [ :org_id, 1 ] ] } # in order: a Hash == ignores it
      Brand.create!(name: "Brahma")
      any_owner = Brand.where(key: "brahma").explain["queryPlanner"]
      shared = Brand.shared.where(key: "brahma").explain["queryPlanner"]

      aggregate_failures do
        expect(index.options).to include(unique: true, partial_filter_expression: { key: { "$gt" => "" } })
        expect(Brand.index_specifications.map(&:key)).not_to include({ key: 1 })
        expect(scans(any_owner["winningPlan"])).to eq([ "key_1_org_id_1" ])
        # { org_id, key } serves it as well; which of the two wins is the data's: the unique one is a candidate
        expect(scans([ shared["winningPlan"], shared["rejectedPlans"] ])).to include("key_1_org_id_1")
      end
    end

    it "is on the database as declared" do
      unique = Brand.collection.indexes.find { |index| index["key"].to_a == [ [ "key", 1 ], [ "org_id", 1 ] ] }

      expect(unique).to include("unique" => true, "partialFilterExpression" => { "key" => { "$gt" => "" } })
    end

    # A prefix regex implies no partial filter: without the plain one it scans.
    it "takes a prefix of an owner's keys on a plain one" do
      index = Brand.index_specifications.find { |spec| spec.key.to_a == [ [ :org_id, 1 ], [ :key, 1 ] ] }
      Brand.create!(name: "Brahma")
      plan = Brand.for(Org.create!(name: "Mercado do Zé")).starting_with("bra").explain["queryPlanner"]["winningPlan"]

      aggregate_failures do
        expect(index).to be_present
        expect(index&.options.to_h).not_to include(:unique, :partial_filter_expression)
        expect(scans(plan)).to include("org_id_1_key_1").and all(eq("org_id_1_key_1"))
      end
    end
  end

  describe "who owns it" do
    let(:org)   { Org.create!(name: "Mercado do Zé") }
    let(:other) { Org.create!(name: "Outro Mercado") }
    let!(:shared) { Brand.create!(name: "Brahma") }
    let!(:own)    { Brand.create!(name: "Marca do Zé", org_id: org.id) }
    let!(:theirs) { Brand.create!(name: "Marca do Outro", org_id: other.id) }

    it "is the shared catalogue's with no org" do
      expect(Brand.shared.to_a).to eq([ shared ])
    end

    it "is one org's alone, by the org or its id" do
      expect(Brand.of(org).to_a).to eq([ own ])
      expect(Brand.of(org.id).to_a).to eq([ own ])
    end

    it "is shared and its own for an org, never another's" do
      expect(Brand.for(org).to_a).to contain_exactly(shared, own)
      expect(Brand.for(org.id).to_a).to contain_exactly(shared, own)
      expect(Brand.for(nil).to_a).to eq([ shared ])
    end

    it "lets two orgs each own the same name" do
      Brand.create!(name: "Da Casa", org_id: org.id)

      expect(Brand.new(name: "DA CASA", org_id: other.id)).to be_valid
    end

    it "refuses the same name twice in one org" do
      Brand.create!(name: "Da Casa", org_id: org.id)

      expect(Brand.new(name: "Da Casa", org_id: org.id)).not_to be_valid
    end

    it "is held by the unique index when the check is skipped" do
      Brand.create!(name: "Da Casa", org_id: org.id)
      twin = Brand.new(name: "Da Casa", key: "da casa", org_id: org.id)

      expect { twin.save!(validate: false) }.to raise_error(Mongo::Error::OperationFailure)
      expect { Brand.new(name: "Da Casa", key: "da casa", org_id: other.id).save!(validate: false) }.not_to raise_error
    end

    it "may not shadow a shared brand: the org picks that one" do
      copy = Brand.new(name: "BRAHMA", org_id: org.id)

      expect(copy).not_to be_valid
      expect(copy.errors.details[:name]).to include(error: :taken)
      expect(copy.errors[:name]).to include(I18n.t("mongoid.errors.models.brand.attributes.name.taken"))
    end

    it "lets the shared catalogue take a name an org already owns" do
      expect(Brand.new(name: "Marca do Zé")).to be_valid
    end

    it "keeps an org's brand editable once the shared catalogue has its name" do
      Brand.create!(name: "Marca do Zé")

      expect(own.reload.update(info: "a nossa")).to be true
    end

    describe "a change of owner" do
      it "is refused while another owner's product is filed under it" do
        Drink.create!(name: "Caipirinha", org_id: org.id, brand: own)

        expect(own.update(org_id: other.id)).to be false
        expect(own.errors.details[:products]).to include(error: :other_owner)
        expect(own.errors[:products]).to include(I18n.t("mongoid.errors.models.brand.attributes.products.other_owner"))
        expect(own.reload.org_id).to eq(org.id)
      end

      it "is refused for a shared brand with no key yet, the shared catalogue's products on it" do
        legacy = Brand.new(name: "Velha")
        legacy.collection.insert_one(legacy.as_document.except("key"))
        Drink.create!(name: "Velha Pinga", brand: legacy)

        expect(Brand.find(legacy.id).update(org_id: org.id)).to be false
      end

      it "is refused for a shared brand with the shared catalogue's products on it" do
        Drink.create!(name: "Brahma Chopp", brand: shared)

        expect(shared.update(org_id: org.id)).to be false
        expect(shared.errors.details[:products]).to include(error: :other_owner)
      end

      it "goes through when only the new owner's products, or none, are on it" do
        Drink.create!(name: "Caipirinha", org_id: org.id, brand: own)

        expect(own.update(org_id: nil)).to be true
        expect(theirs.update(org_id: org.id)).to be true
      end

      it "takes a shared brand nobody else uses into an org: it shadows nothing but itself" do
        Drink.create!(name: "Brahma da Casa", org_id: org.id, brand: shared)

        expect(shared.update(org_id: org.id)).to be true
      end
    end
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

    it "finds a brand behind what a paste brings along: a BOM, a zero-width space" do
      expect(Brand.named("\uFEFFAntártica\u200B")).to eq(brand)
      expect(Brand.named("\u200B")).to be_nil
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

    context "with an org" do
      let(:org)   { Org.create!(name: "Mercado do Zé") }
      let(:other) { Org.create!(name: "Outro Mercado") }
      let!(:own)  { Brand.create!(name: "Da Casa", org_id: org.id) }

      it "finds the org's own" do
        expect(Brand.named("da casa", org: org)).to eq(own)
        expect(Brand.named("da casa", org: org.id)).to eq(own)
      end

      it "finds the shared one the org has no copy of" do
        expect(Brand.named("antartica", org: org)).to eq(brand)
      end

      it "finds the org's own before the shared one" do
        legacy = Brand.new(name: "Skol", key: "skol", org_id: org.id)
        legacy.collection.insert_one(legacy.as_document) # before the shadow check
        Brand.create!(name: "Skol")

        expect(Brand.named("SKOL", org: org)).to eq(legacy)
      end

      it "finds the org's own by an alias before a shared key" do
        own.update!(name: "Da Casa Nova")
        shared = Brand.new(name: "Da Casa", key: "da casa")
        shared.collection.insert_one(shared.as_document)

        expect(Brand.named("Da Casa", org: org)).to eq(own)
      end

      it "never finds another org's, and without an org only the shared" do
        expect(Brand.named("da casa", org: other)).to be_nil
        expect(Brand.named("da casa")).to be_nil
      end
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

    context "with an org" do
      let(:org)   { Org.create!(name: "Mercado do Zé") }
      let(:other) { Org.create!(name: "Outro Mercado") }

      before do
        Brand.create!(name: "Bramha Caseira", org_id: org.id)
        Brand.create!(name: "Brava", org_id: other.id)
      end

      it "reads the shared catalogue and the org's own, never another org's" do
        expect(Brand.search("bra", org: org).map(&:name)).to eq([ "Brahma", "Bramha Caseira" ])
        expect(Brand.search(nil, org: org).count).to eq(4)
      end

      it "is the shared catalogue without one" do
        expect(Brand.search("bra").map(&:name)).to eq([ "Brahma" ])
      end
    end
  end

  describe ".starting_with" do
    it "narrows whatever scope it is called on, never widens it" do
      org = Org.create!(name: "Mercado do Zé")
      Brand.create!(name: "Brahma")
      own = Brand.create!(name: "Bramha Caseira", org_id: org.id)

      expect(Brand.of(org).starting_with("bra").to_a).to eq([ own ])
      expect(Brand.for(org).starting_with("bra").map(&:name)).to eq([ "Brahma", "Bramha Caseira" ])
    end
  end

  describe ".backfill_keys" do
    def legacy(name, org_id = nil)
      brand = Brand.new(name: name, org_id: org_id)
      brand.collection.insert_one(brand.as_document.except("key"))
      brand
    end

    it "gives an old brand its key, and hands back a second spelling of one owner's name" do
      Brand.create!(name: "Antártica")
      old = legacy("Skol")
      legacy("ANTARTICA")

      expect(Brand.backfill_keys).to eq([ "ANTARTICA" ])
      expect(old.reload.key).to eq("skol")
    end

    it "checks a clash within the brand's own owner" do
      org = Org.create!(name: "Mercado do Zé")
      Brand.create!(name: "Da Casa", org_id: org.id)
      old = legacy("Da Casa")

      expect(Brand.backfill_keys).to eq([])
      expect(old.reload.key).to eq("da casa")
    end

    it "hands back an org's spelling of a shared brand: it would shadow it" do
      org = Org.create!(name: "Mercado do Zé")
      Brand.create!(name: "Brahma")
      old = legacy("BRAHMA", org.id)

      expect(Brand.backfill_keys).to eq([ "BRAHMA" ])
      expect(old.reload.key).to be_nil
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

  describe "a rename" do
    it "takes its products' search words along, and is no edit of theirs" do
      brand = Brand.create!(name: "Antartica")
      product = Product.new(name: "Original", brand: brand, source: "off")
      product.importing = true
      product.save!

      Brand.find(brand.id).update!(name: "Antarctica") # as the admin's form loads it

      expect(product.reload.tokens).to contain_exactly("original", "antarctica")
      expect(product.source).to eq("off")
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

  # What leaves in a dump and what an import writes: the shared catalogue only.
  describe "the open catalogue" do
    let(:org) { Org.create!(name: "Mercado do Zé") }

    it "dumps no org's brand, not even one a shared product was forced onto" do
      shared = Brand.create!(name: "Brahma")
      own = Brand.create!(name: "Marca do Zé", org_id: org.id)
      Drink.create!(name: "Brahma Chopp", code: "7891991010023", brand: shared)
      forced = Drink.create!(name: "Arroz", code: "7891000315507")
      forced.set(brand_id: own.id) # past the check
      Drink.create!(name: "Feijão", code: "7891000100103", org_id: org.id, brand: own)

      records = Openmarket::Catalogue.records.to_a

      expect(records.select { |record| record["type"] == "brand" }.map { |record| record["name"] }).to eq([ "Brahma" ])
      expect(records.map { |record| record["code"] }.compact).to contain_exactly("7891991010023", "7891000315507")
      expect(records.to_s).not_to include("Marca do Zé")
    end

    it "restores into shared brands, beside an org's own of the same name" do
      own = Brand.create!(name: "Brahma", org_id: org.id)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "dump.ndjson")
        Openmarket::Dump.write(path, [
          { "type" => "brand", "name" => "Brahma", "country" => "BR" },
          { "type" => "drink", "code" => "7891991010023", "name" => { "pt" => "Cerveja Brahma" }, "brand" => "Brahma" }
        ])
        Openmarket::Catalogue.restore(path)
      end

      brand = Product.find_by(code: "7891991010023").brand
      expect(brand).not_to eq(own)
      expect(brand).to have_attributes(org_id: nil, country: "BR")
      expect(own.reload.country).to be_nil
    end
  end

  describe "#aliases" do
    it "keeps the key of a name it had, so the next import finds it" do
      brand = Brand.create!(name: "Antartica")
      brand.update!(name: "Antarctica")

      expect(brand.aliases).to eq(%w[ antartica ])
      expect(Brand.named("Antartica")).to eq(brand)
    end

    it "keeps no alias for a new casing of the same name" do
      brand = Brand.create!(name: "BRAHMA")
      brand.update!(name: "Brahma")

      expect(brand.aliases).to eq([])
    end
  end
end
