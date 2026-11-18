class BrandsController < ApplicationController
  before_action :set_brand, only: %i[ show edit update destroy ]

  # GET /brands or /brands.json — ?search= is the start of a name.
  def index
    @pagy, @brands = pagy(brands.starting_with(params[:search]), limit: 50)
  end

  # GET /brands/1 or /brands/1.json — and the products filed under it.
  def show
    @pagy, @products = pagy(products.where(brand_id: @brand.id), limit: 50)
  end

  # GET /brands/search.json?q=amb — what to offer while someone types a brand.
  def search
    @brands = brands.starting_with(params[:q]).limit(20)
    render :index, formats: :json
  end

  # GET /brands/new
  def new
    @brand = Brand.new
  end

  # GET /brands/1/edit
  def edit
  end

  # POST /brands or /brands.json
  def create
    @brand = Brand.new(brand_params)

    respond_to do |format|
      if @brand.save
        format.html { redirect_to @brand, notice: "Brand was successfully created." }
        format.json { render :show, status: :created, location: @brand }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @brand.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /brands/1 or /brands/1.json
  def update
    respond_to do |format|
      if @brand.update(brand_params)
        format.html { redirect_to @brand, notice: "Brand was successfully updated." }
        format.json { render :show, status: :ok, location: @brand }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @brand.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /brands/1 or /brands/1.json — refused while it has products.
  def destroy
    respond_to do |format|
      if @brand.destroy
        format.html { redirect_to brands_path, status: :see_other, notice: "Brand was successfully destroyed." }
        format.json { head :no_content }
      else
        format.html { redirect_to @brand, status: :see_other, alert: @brand.errors.full_messages.to_sentence }
        format.json { render json: @brand.errors, status: :unprocessable_entity }
      end
    end
  end

  private

  # What this controller lists, shows, edits and offers while someone types:
  # the shared catalogue's brands. An app that shows an org its own overrides
  # this, as ProductsController#products (README § Your app decides):
  #
  #   def brands = Brand.for(current_org)   # its own beside the catalogue
  #
  # and Brand.of(current_org) for edit, update and destroy: the shared ones
  # are the catalogue's to write (README has the line).
  def brands = Brand.shared

  # The products a brand's page lists: the shared catalogue, as in
  # ProductsController#products. An app that shows more overrides both.
  def products = Product.shared

  def set_brand
    @brand = brands.find(params.expect(:id))
  end

  # Only allow a list of trusted parameters through. `key` and `source` are
  # the catalogue's own: one is made from the name, the other says who wrote it.
  # No org: filing a brand under one is the app's, which adds it here —
  # `super.merge(org_id: current_org.id)`.
  def brand_params
    params.expect(brand: [ :name, :info, :wikidata, :country, :site, :logo ])
  end
end
