json.extract! product, :id, :name, :kind, :brand, :size, :acl, :created_at, :updated_at
json.url product_url(product, format: :json)
