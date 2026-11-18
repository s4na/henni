class OffersController < ActionController::Base
  def show
    @offer = Offer.find(params[:id])
    respond_to do |format|
      format.html
      format.json { render json: { discount: @offer.discount? } }
    end
  end
end
