require 'test_helper'

class RemotePayoneTest < Test::Unit::TestCase


  def setup
    @gateway = PayoneGateway.new(fixtures(:payone))

    @amount = 100
    @credit_card = credit_card('4000100011112224')
    @declined_card = credit_card('1111111111111111')

    @options = {
      :order_id => '1',
      :billing_address => address,
      :description => 'Store Purchase',
      :reference => SecureRandom.random_number(1000000)
    }
  end

  def test_successful_purchase
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'This transaction has been approved', response.message
  end

  def test_unsuccessful_purchase
    assert response = @gateway.purchase(@amount, @declined_card, @options)
    assert_failure response
    assert_equal 'This transaction has not been approved', response.message
  end

  def test_authorize_and_capture
    amount = @amount
    assert auth = @gateway.authorize(amount, @credit_card, @options)
    assert_success auth
    assert_equal 'This transaction has been approved', auth.message
    assert auth.authorization
    assert capture = @gateway.capture(amount, auth.authorization)
    assert_success capture
  end

  def test_failed_capture
    assert response = @gateway.capture(@amount, '')
    assert_failure response
    assert_equal 'This transaction has not been approved', response.message
  end

  def test_invalid_login
    gateway = PayoneGateway.new(
                :login => '',
                :password => '',
                :sub_account_id => '',
                :key => '',
                :reference => ''
              )
    assert response = gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal 'This transaction has not been approved', response.message
  end
end
