require "rails_helper"

# The engine knows nothing of who asks: as it ships it shows the shared
# catalogue. An app that shows more overrides — here BarProductsController
# (spec/dummy), the example README § Your app decides gives, at /bar/products.
RSpec.describe "What an app overrides", type: :request do
  let!(:ze)     { Org.create!(name: "Bar do Zé") }
  let!(:other)  { Org.create!(name: "Outro Bar") }
  let!(:brand)  { Brand.create!(name: "Brahma") }
  let!(:brahma) { Drink.create!(name: "Brahma Chopp", code: "7891991010023", brand: brand) }
  let!(:house)  { Drink.create!(name: "Caipirinha da Casa", code: "HOUSE-1", org: ze, brand: brand) }
  let!(:theirs) { Drink.create!(name: "Caipirinha do Outro", code: "HOUSE-2", org: other) }

  def codes = response.parsed_body.map { |row| row["code"] }

  describe "nothing: the engine as it ships" do
    it "lists the shared catalogue" do
      get products_url(format: :json)

      expect(codes).to eq([ brahma.code ])
    end

    it "shows no org's own" do
      get product_url(house, format: :json)

      expect(response).to have_http_status(:not_found)
    end

    it "scans the shared catalogue" do
      get lookup_products_url(code: house.code, format: :json)

      expect(response).to have_http_status(:not_found)
    end

    it "lists a brand's shared products" do
      get brand_url(brand, format: :json)

      expect(response.parsed_body["products"].map { |row| row["code"] }).to eq([ brahma.code ])
    end

    it "takes no org from a form" do
      post products_url, params: { product: { type: "Drink", name: "Caipirinha", org_id: other.id.to_s } }

      expect(Product.find_by(name: "Caipirinha").org_id).to be_nil
    end
  end

  describe "`products`" do
    it "lists the app's own beside the shared catalogue, never another org's" do
      get bar_products_url(format: :json)

      expect(codes).to contain_exactly(brahma.code, house.code)
    end

    it "searches within them" do
      get bar_products_url(search: "caipi", format: :json)

      expect(codes).to eq([ house.code ])
    end

    it "shows no other org's" do
      get bar_product_url(theirs, format: :json)

      expect(response).to have_http_status(:not_found)
    end

    it "writes only the app's own" do
      patch bar_product_url(brahma, format: :json), params: { product: { name: "Brahma da Casa" } }

      expect(response).to have_http_status(:not_found)
      expect(brahma.reload.name).to eq("Brahma Chopp")
    end

    it "edits the app's own" do
      patch bar_product_url(house, format: :json), params: { product: { name: "Caipirinha de Limão" } }

      expect(house.reload).to have_attributes(name: "Caipirinha de Limão", org_id: ze.id)
    end
  end

  describe "`product_params`" do
    it "files what the app's form makes under the app's org" do
      post bar_products_url(format: :json), params: { product: { type: "Drink", name: "Batida de Coco", org_id: other.id.to_s } }

      expect(response).to have_http_status(:created)
      expect(Product.find_by(name: "Batida de Coco").org_id).to eq(ze.id)
    end
  end

  describe "a scan through `products`" do
    it "finds the app's own before the shared one" do
      own = Drink.create!(name: "Brahma da Casa", code: brahma.code, org: ze)
      get lookup_bar_products_url(code: "7 891991 010023", format: :json)

      expect(response.parsed_body["id"]).to eq(own.id.to_s)
    end
  end
end
