class ItemsController < ApplicationController
  before_action :set_item, only: %i[ show edit update destroy ]

  # GET /items or /items.json
  def index
    @pagy, @items = pagy(Item.search(params[:search]), limit: 50)
  end

  # GET /items/1 or /items/1.json
  def show
  end

  # GET /items/new
  def new
    @item = params[:type]&.classify&.constantize&.new || Item.new
    @item.type = params[:type] if params[:type].in?(['Drink', 'Food'])
  end

  # GET /items/1/edit
  def edit
  end

  # POST /items or /items.json
  def create
    item_class = item_params[:type]&.classify&.constantize || Item
    @item = item_class.new(item_params.except(:type))
    @item.type = item_params[:type] if item_params[:type].in?(['Drink', 'Food'])

    respond_to do |format|
      if @item.save
        format.html { redirect_to @item, notice: "Item was successfully created." }
        format.json { render :show, status: :created, location: @item }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @item.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /items/1 or /items/1.json
  def update
    respond_to do |format|
      if @item.update(item_params.except(:type))
        format.html { redirect_to @item, notice: "Item was successfully updated." }
        format.json { render :show, status: :ok, location: @item }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @item.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /items/1 or /items/1.json
  def destroy
    @item.destroy!

    respond_to do |format|
      format.html { redirect_to items_path, status: :see_other, notice: "Item was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
  # Use callbacks to share common setup or constraints between actions.
  def set_item
    @item = Item.find(params.expect(:id))
  end

  # Only allow a list of trusted parameters through.
  def item_params
    params.expect(item: [:type, :name, :kind, :code, :pack, :brand, :size, :acl])
  end
end
