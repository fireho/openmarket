# The host's tenant: what owns a product that is not the shared catalogue's.
class Org
  include Mongoid::Document

  field :name, type: String
end
