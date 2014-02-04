class AuthorizedKeysController < ApplicationController
  def index_pane_list
    %w(recent help)
  end

  def new
    super
    @object.authorized_user_uuid = current_user.uuid if current_user
    @object.key_type = 'SSH'
  end

  def create
    defaults = { authorized_user_uuid: current_user.uuid, key_type: 'SSH' }
    @object = AuthorizedKey.new defaults.merge(params[:authorized_key] || {})
    super
  end
end
