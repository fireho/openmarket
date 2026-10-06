# A brand as the open catalogue knows it. The id is a string; `key` is only
# how names meet, never shown.
json.id brand.id.to_s
json.extract! brand, :name, :info, :wikidata, :country, :site, :logo, :source, :created_at, :updated_at
json.url brand_url(brand, format: :json)
