class Brand
  include Mongoid::Document
  include Mongoid::Timestamps

  field :name, type: String
  field :info, type: String

  has_many :items

  validates :name, presence: true, uniqueness: true
  validates :info, presence: true
end