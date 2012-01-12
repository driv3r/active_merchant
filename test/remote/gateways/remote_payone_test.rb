require 'test_helper'

class RemotePayoneTest < Test::Unit::TestCase


  def setup
    @gateway = PayoneGateway.new(fixtures(:payone))

    @amount = 100
    @credit_card = credit_card('5453010000080200', :type => :master)
    @declined_card = credit_card('1111111111111111')
    @direct_debit = DirectDebit.new
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

  def test_successful_purchase_using_direct_debit
    @options[:clearingtype] = 'elv'
    assert response = @gateway.purchase(@amount, @direct_debit, @options)
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

  def test_authorize_and_capture_using_direct_debit
    @options[:clearingtype] = 'elv'
    amount = @amount
    assert auth = @gateway.authorize(amount, @direct_debit, @options)
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
    assert auth = @gateway.authorize(@amount, @credit_card, @options)
    assert auth.authorization

    assert capture = @gateway.capture(@amount, auth.authorization)
    assert capture.authorization

    sleep 120

    @options[:sequencenumber] = 2
    assert refund = @gateway.refund(@amount, capture.authorization, @options) #amount should be positive integer
    assert_success refund
    assert refund.authorization

    assert_equal 'This transaction has been approved', refund.message
  end

  def test_successful_refund_with_purchase

    assert purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert purchase.authorization

    sleep 150

    @options[:sequencenumber] = 1

    assert refund = @gateway.refund(@amount, purchase.authorization, @options) #amount should be positive integer
    assert_success refund
    assert refund.authorization

    assert_equal 'This transaction has been approved', refund.message
  end

  def test_unsuccessful_refund

    assert purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert purchase.authorization

    @options[:sequencenumber] = 1

    assert refund = @gateway.refund(@amount*2, purchase.authorization, @options)
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

class DirectDebit
  attr_accessor :first_name, :last_name, :country, :account_number, :sort_code

  def initialize(params= {})
    @first_name     = params[:first_name]     || "Katja"
    @last_name      = params[:last_name]      || "Koplin"
    @country        = params[:country]        || "DE"
    @account_number = params[:account_number] || "2599100003"
    @sort_code      = params[:sort_code]      || "12345678"
  end
end
