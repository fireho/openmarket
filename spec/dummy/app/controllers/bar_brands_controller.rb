# An org's brands, as README § Your app decides writes it: the engine's
# controller, two methods overridden. Routed at /bar/brands.
class BarBrandsController < BrandsController
  private

  def brands = action_name.in?(%w[ edit update destroy ]) ? Brand.of(current_org) : Brand.for(current_org)
  def brand_params = super.merge(org_id: current_org.id)

  def current_org = Org.find_by(name: "Bar do Zé")
end
