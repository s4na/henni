require "test_helper"

class StoreConnectionTest < ActionCable::Connection::TestCase
  tests ApplicationCable::Connection

  def test_identifies_the_session
    connect session: { session_id: "shopper" }
    assert_equal "shopper", connection.session_id
  end
end
