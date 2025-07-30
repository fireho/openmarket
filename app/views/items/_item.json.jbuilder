json.extract! item, :id, :name, :kind, :brand, :size, :acl, :created_at, :updated_at
json.url item_url(item, format: :json)
