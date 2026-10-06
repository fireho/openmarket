require "rails_helper"

RSpec.describe "/brands", type: :request do
  let(:valid_attributes) {
    Fabricate.attributes_for(:brand)
  }

  let(:invalid_attributes) {
    { name: "" }
  }

  def names = response.parsed_body.map { |row| row["name"] }

  describe "GET /index" do
    it "renders a successful response" do
      Brand.create! valid_attributes
      get brands_url
      expect(response).to be_successful
    end

    it "lists the brands by name, case and accents aside, as json" do
      Brand.create!(name: "Skol")
      Brand.create!(name: "ambev")
      Brand.create!(name: "Antártica")
      get brands_url(format: :json)

      expect(names).to eq(%w[ ambev Antártica Skol ])
    end

    it "finds the brands a name starts with" do
      Brand.create!(name: "Antártica")
      Brand.create!(name: "Brahma")
      get brands_url(search: "ANTAR", format: :json)

      expect(names).to eq([ "Antártica" ])
    end
  end

  describe "GET /show" do
    it "renders a successful response" do
      brand = Brand.create! valid_attributes
      Fabricate(:drink, brand: brand)
      get brand_url(brand)
      expect(response).to be_successful
    end

    it "counts its products and links them, as json" do
      brand = Brand.create! valid_attributes
      drink = Fabricate(:drink, brand: brand)
      get brand_url(brand, format: :json)

      expect(response.parsed_body).to include("name" => brand.name, "products_count" => 1)
      expect(response.parsed_body["products"].map { |row| row["id"] }).to eq([ drink.id.to_s ])
      expect(response.parsed_body["products"].first["url"]).to end_with("/products/#{drink.id}.json")
    end

    it "does not hand out the lookup key" do
      brand = Brand.create! valid_attributes
      get brand_url(brand, format: :json)

      expect(response.parsed_body.keys).not_to include("key", "_id")
    end
  end

  describe "GET /search" do
    it "offers the brands a name starts with, as json" do
      Brand.create!(name: "Antártica")
      Brand.create!(name: "Brahma")
      get search_brands_url(q: "antar", format: :json)

      expect(response).to be_successful
      expect(names).to eq([ "Antártica" ])
    end

    it "offers 20 at most" do
      21.times { |n| Brand.create!(name: "Marca #{n}") }
      get search_brands_url(q: "marca", format: :json)

      expect(response.parsed_body.size).to eq(20)
    end
  end

  describe "GET /new" do
    it "renders a successful response" do
      get new_brand_url
      expect(response).to be_successful
    end
  end

  describe "GET /edit" do
    it "renders a successful response" do
      brand = Brand.create! valid_attributes
      get edit_brand_url(brand)
      expect(response).to be_successful
    end
  end

  describe "POST /create" do
    context "with valid parameters" do
      it "creates a new Brand" do
        expect {
          post brands_url, params: { brand: valid_attributes }
        }.to change(Brand, :count).by(1)
      end

      it "redirects to the created brand" do
        post brands_url, params: { brand: valid_attributes }
        expect(response).to redirect_to(brand_url(Brand.last))
      end

      it "keeps what a person typed, and stores nothing for what they did not" do
        post brands_url, params: { brand: { name: "Brahma", country: "br", wikidata: "", site: "" } }
        brand = Brand.last

        expect([ brand.name, brand.country, brand.source ]).to eq([ "Brahma", "BR", nil ])
        expect(Brand.where(wikidata: nil, site: nil)).to include(brand)
      end
    end

    context "with invalid parameters" do
      it "does not create a new Brand" do
        expect {
          post brands_url, params: { brand: invalid_attributes }
        }.to change(Brand, :count).by(0)
      end

      it "renders a response with 422 status (i.e. to display the 'new' template)" do
        post brands_url, params: { brand: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "refuses another spelling of a name that is taken" do
        Brand.create!(name: "Antártica")

        expect {
          post brands_url, params: { brand: { name: "ANTARTICA" } }, as: :json
        }.not_to change(Brand, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "PATCH /update" do
    context "with valid parameters" do
      it "updates the requested brand" do
        brand = Brand.create! valid_attributes
        patch brand_url(brand), params: { brand: { name: "Cervejaria Nova", site: "https://example.com" } }
        brand.reload
        expect(brand.name).to eq("Cervejaria Nova")
        expect(brand.site).to eq("https://example.com")
      end

      it "redirects to the brand" do
        brand = Brand.create! valid_attributes
        patch brand_url(brand), params: { brand: { name: "Cervejaria Nova" } }
        expect(response).to redirect_to(brand_url(brand))
      end
    end

    context "with invalid parameters" do
      it "renders a response with 422 status (i.e. to display the 'edit' template)" do
        brand = Brand.create! valid_attributes
        patch brand_url(brand), params: { brand: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "DELETE /destroy" do
    it "destroys the requested brand" do
      brand = Brand.create! valid_attributes
      expect {
        delete brand_url(brand)
      }.to change(Brand, :count).by(-1)
    end

    it "redirects to the brands list" do
      brand = Brand.create! valid_attributes
      delete brand_url(brand)
      expect(response).to redirect_to(brands_url)
    end

    it "keeps a brand that still has products" do
      brand = Brand.create! valid_attributes
      Fabricate(:drink, brand: brand)

      expect {
        delete brand_url(brand)
      }.not_to change(Brand, :count)
      expect(response).to redirect_to(brand_url(brand))
    end

    it "says why, as json" do
      brand = Brand.create! valid_attributes
      Fabricate(:drink, brand: brand)
      delete brand_url(brand, format: :json)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to have_key("products")
    end
  end
end
