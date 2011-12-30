require 'test_helper'

class RemotePayoneTest < Test::Unit::TestCase


  def setup
    @gateway = PayoneGateway.new(fixtures(:payone))

    @amount = 100
    @refund_amount = -100
    @credit_card = credit_card('5453010000080200', :type => :master)
    @declined_card = credit_card('1111111111111111')

    @options = {
      :order_id => "AMRT#{SecureRandom.random_number(1000000)}",
      :billing_address => address,
      :description => 'Store Purchase'
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

  def test_successful_refund_with_authorize_and_capture
    @options[:sequencenumber] = 2

    assert auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth
    assert auth.authorization

    assert capture = @gateway.capture(@amount, auth.authorization)
    assert_success capture
    assert capture.authorization

    assert refund = @gateway.refund(@refund_amount, capture.authorization, @options)
    assert_success refund
    assert refund.authorization

    assert_equal 'This transaction has been approved', refund.message
  end

  def test_successful_refund_with_purchase
    @options[:sequencenumber] = 1

    assert purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase
    assert purchase.authorization

    assert refund = @gateway.refund(@refund_amount, purchase.authorization, @options)
    assert_success refund
    assert refund.authorization

    assert_equal 'This transaction has been approved', refund.message
  end

  def test_unsuccessful_refund
    @options[:sequencenumber] = 1

    assert purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase
    assert purchase.authorization

    assert refund = @gateway.refund(@refund_amount*2, purchase.authorization, @options)
    assert_failure refund

    assert_equal 'This transaction has not been approved', refund.message
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
