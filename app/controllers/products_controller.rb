class ProductsController < ApplicationController
  before_action :set_product, only: %i[ show edit update destroy ]
  helper_method :products

  # GET /products or /products.json
  def index
    @pagy, @products = pagy(products.search(params[:search]), limit: 50)
  end

  # GET /products/1 or /products/1.json
  def show
  end

  # GET /products/lookup/7891991010023 or .json — the scan: a barcode, in any
  # spelling, and the one product it names, an owner's own before the shared
  # one. 404 when `products` lacks it.
  def lookup
    @product = products.with_code(params[:code]).order_by(org_id: -1).first
    return head :not_found unless @product

    render :show
  end

  # GET /products/search.json?q=brah — what to offer while someone types.
  def search
    @products = products.search(params[:q]).limit(20)
    render :index, formats: :json
  end

  # The shapes a form may ask for. A name from the request never becomes a
  # class by itself: `constantize` on user input reaches any class in the app.
  TYPES = { "Drink" => Drink, "Food" => Food }.freeze

  # GET /products/new
  def new
    klass = TYPES[params[:type].to_s.camelize] # "drink", as the JSON says it, or "Drink"
    @product = (klass || Product).new
  end

  # GET /products/1/edit
  def edit
  end

  # POST /products or /products.json
  def create
    product_class = TYPES[product_params[:type].to_s.camelize]
    @product = (product_class || Product).new(product_params.except(:type))

    respond_to do |format|
      if @product.save
        format.html { redirect_to @product, notice: "Product was successfully created." }
        format.json { render :show, status: :created, location: @product }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @product.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /products/1 or /products/1.json
  def update
    respond_to do |format|
      if @product.update(product_params.except(:type))
        format.html { redirect_to @product, notice: "Product was successfully updated." }
        format.json { render :show, status: :ok, location: @product }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @product.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /products/1 or /products/1.json
  def destroy
    @product.destroy!

    respond_to do |format|
      format.html { redirect_to products_path, status: :see_other, notice: "Product was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # What this controller reads, edits and scans: the shared catalogue. Who
  # asks, and what else they may see, is the app's to say — it overrides
  # this (README § Your app decides):
  #
  #   def products = Product.for(current_org)   # its own beside the catalogue
  def products = Product.shared

  def set_product
    @product = products.find(params.expect(:id))
  end

  # What a form may write. No org: filing a product under one is the app's,
  # which adds it here — `super.merge(org_id: current_org.id)`.
  def product_params
    params.expect(product: [ :type, :name, :info, :kind, :code, :pack, :brand_id, :brand_name, :size, :acl, :image, :quantity ])
  end
end
