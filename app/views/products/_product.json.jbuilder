# What an app needs to fill a form from a scan. The brand is its name, the
# id is a string; nothing of the host's (org, sku, uses) goes out.
json.id product.id.to_s
json.extract! product, :code, :name, :image, :quantity
json.type product.drink? ? "drink" : (product.food? ? "food" : "product")
json.brand product.brand&.name
json.extract! product, :kind, :size if product.respond_to?(:kind)
json.pack product.pack if product.respond_to?(:pack)
json.acl product.acl if product.respond_to?(:acl)
json.extract! product, :countries, :source, :created_at, :updated_at
json.url product_url(product, format: :json)
