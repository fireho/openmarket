require "rails_helper"

# The engine knows nothing of who asks: as it ships it shows the shared
# catalogue. An app that shows more overrides — here BarProductsController
# (spec/dummy), the example README § Your app decides gives, at /bar/products.
RSpec.describe "What an app overrides", type: :request do
  let!(:ze)     { Org.create!(name: "Bar do Zé") }
  let!(:other)  { Org.create!(name: "Outro Bar") }
  let!(:brand)  { Brand.create!(name: "Brahma") }
  let!(:brahma) { Drink.create!(name: "Brahma Chopp", code: "7891991010023", brand: brand) }
  let!(:house)  { Drink.create!(name: "Caipirinha da Casa", code: "HOUSE-1", org_id: ze.id, brand: brand) }
  let!(:theirs) { Drink.create!(name: "Caipirinha do Outro", code: "HOUSE-2", org_id: other.id) }

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

    it "counts the shelf it lists" do
      get products_url

      expect(response.body).to include(I18n.t("openmarket.products.totals", total: 1, drinks: 1, foods: 0))
    end

    it "offers no Delete for a brand whose products it does not list" do
      kept = Brand.create!(name: "Da Casa")
      Drink.create!(name: "Batida", org_id: ze.id, brand: kept)
      get brand_url(kept)

      expect(response.body).not_to include("Excluir")
    end

    it "takes no org from a form" do
      post products_url, params: { product: { type: "Drink", name: "Caipirinha", org_id: other.id.to_s } }

      expect(Product.find_by(name: "Caipirinha").org_id).to be_nil
    end

    it "lists, searches and shows only the shared brands" do
      own = Brand.create!(name: "Brava do Zé", org_id: ze.id)

      get brands_url(format: :json)
      expect(response.parsed_body.map { |row| row["name"] }).to eq([ "Brahma" ])

      get search_brands_url(q: "bra", format: :json)
      expect(response.parsed_body.map { |row| row["name"] }).to eq([ "Brahma" ])

      get brand_url(own, format: :json)
      expect(response).to have_http_status(:not_found)
    end

    it "edits, updates and destroys no org's brand" do
      own = Brand.create!(name: "Brava do Zé", org_id: ze.id)

      get edit_brand_url(own)
      expect(response).to have_http_status(:not_found)
      patch brand_url(own, format: :json), params: { brand: { name: "Tomada" } }
      expect(response).to have_http_status(:not_found)
      delete brand_url(own, format: :json)
      expect(response).to have_http_status(:not_found)
      expect(own.reload.name).to eq("Brava do Zé")
    end

    it "takes no org from a brand form" do
      post brands_url(format: :json), params: { brand: { name: "Nova", org_id: other.id.to_s } }

      expect(Brand.find_by(name: "Nova").org_id).to be_nil
    end
  end

  describe "`brands`" do
    let!(:own)     { Brand.create!(name: "Brava do Zé", org_id: ze.id) }
    let!(:foreign) { Brand.create!(name: "Brasa do Outro", org_id: other.id) }

    def names = response.parsed_body.map { |row| row["name"] }

    it "lists and searches the app's own beside the shared ones, never another org's" do
      get bar_brands_url(format: :json)
      expect(names).to eq([ "Brahma", "Brava do Zé" ])

      get bar_brands_url(search: "brav", format: :json)
      expect(names).to eq([ "Brava do Zé" ])

      get search_bar_brands_url(q: "bra", format: :json)
      expect(names).to eq([ "Brahma", "Brava do Zé" ])
    end

    it "shows the app's own, and no other org's" do
      get bar_brand_url(own, format: :json)
      expect(response.parsed_body["name"]).to eq("Brava do Zé")

      get bar_brand_url(foreign, format: :json)
      expect(response).to have_http_status(:not_found)
    end

    it "writes only the app's own" do
      patch bar_brand_url(brand, format: :json), params: { brand: { info: "nossa" } }

      expect(response).to have_http_status(:not_found)
      expect(brand.reload.info).to be_nil
    end

    it "files a brand the app's form makes under the app's org" do
      post bar_brands_url(format: :json), params: { brand: { name: "Marca do Zé", org_id: other.id.to_s } }

      expect(response).to have_http_status(:created)
      expect(Brand.find_by(name: "Marca do Zé").org_id).to eq(ze.id)
    end

    it "refuses an org's copy of a shared brand" do
      post bar_brands_url(format: :json), params: { brand: { name: "BRAHMA" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Brand.of(ze).where(key: "brahma")).not_to exist
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

    it "files a new brand typed on the app's form under the app's org" do
      post bar_products_url(format: :json), params: { product: { type: "Drink", name: "Batida", brand_name: "Coca Colla" } }

      expect(response).to have_http_status(:created)
      expect(Product.find_by(name: "Batida").brand).to have_attributes(name: "Coca Colla", org_id: ze.id)
      expect(Brand.shared.where(key: "coca colla")).not_to exist
    end
  end

  describe "a scan through `products`" do
    it "finds the app's own before the shared one" do
      own = Drink.create!(name: "Brahma da Casa", code: brahma.code, org_id: ze.id)
      get lookup_bar_products_url(code: "7 891991 010023", format: :json)

      expect(response.parsed_body["id"]).to eq(own.id.to_s)
    end
  end
end
