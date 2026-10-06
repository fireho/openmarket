# An org's shelf, as README § Your app decides writes it: the engine's
# controller, two methods overridden. Routed at /bar/products.
class BarProductsController < ProductsController
  private

  def products = action_name.in?(%w[ edit update destroy ]) ? Product.of(current_org) : Product.for(current_org)
  def product_params = super.merge(org_id: current_org.id)

  def current_org = Org.find_by(name: "Bar do Zé")
end
