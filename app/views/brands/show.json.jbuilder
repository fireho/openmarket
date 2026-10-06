json.partial! "brands/brand", brand: @brand

# Its products, a page at a time, as links. Only `show` reads them: create and
# update answer with the brand alone.
if @pagy
  json.products_count @pagy.count
  json.products @products do |product|
    json.id product.id.to_s
    json.extract! product, :code, :name
    json.url product_url(product, format: :json)
  end
  json.next brand_url(@brand, page: @pagy.next, format: :json) if @pagy.next
end
