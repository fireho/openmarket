class ProductsController < ApplicationController
  before_action :set_product, only: %i[ show edit update destroy ]

  # GET /products or /products.json
  def index
    @pagy, @products = pagy(Product.search(params[:search]), limit: 50)
  end

  # GET /products/1 or /products/1.json
  def show
  end

  # GET /products/lookup/7891991010023 or .json — the scan: a barcode, in any
  # spelling, and the one product it names. 404 when the catalogue lacks it.
  def lookup
    @product = Product.lookup(params[:code])
    return head :not_found unless @product

    render :show
  end

  # GET /products/search.json?q=brah — what to offer while someone types.
  def search
    @products = Product.search(params[:q]).limit(20)
    render :index, formats: :json
  end

  # The shapes a form may ask for. A name from the request never becomes a
  # class by itself: `constantize` on user input reaches any class in the app.
  TYPES = { "Drink" => Drink, "Food" => Food }.freeze

  # GET /products/new
  def new
    klass = TYPES[params[:type].to_s.camelize] # "drink", as the JSON says it, or "Drink"
    @product = (klass || Product).new
    @product.type = klass.name if klass
  end

  # GET /products/1/edit
  def edit
  end

  # POST /products or /products.json
  def create
    product_class = TYPES[product_params[:type].to_s.camelize]
    @product = (product_class || Product).new(product_params.except(:type))
    @product.type = product_class.name if product_class

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
  # Use callbacks to share common setup or constraints between actions.
  def set_product
    @product = Product.find(params.expect(:id))
  end

  # Only allow a list of trusted parameters through.
  def product_params
    params.expect(product: [ :type, :name, :info, :kind, :code, :pack, :brand_id, :brand_name, :org_id, :size, :acl, :image, :quantity ])
  end
end
