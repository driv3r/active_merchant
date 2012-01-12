require 'test_helper'

class PayoneTest < Test::Unit::TestCase
  def setup
    @gateway = PayoneGateway.new(
                 :login => '66699',
                 :password => '666999',
                 :key => 'some secret text',
                 :sub_account_id => '555'
               )
    @credit_card = credit_card
    @direct_debit = DirectDebit.new
    @amount = 100
    @options = {
      :order_id => SecureRandom.random_number(1000000),
      :billing_address => address,
      :description => 'Store Purchase',
      :clearing_type => 'cc'
    }
  end

  def test_successful_purchase
    # Purchase with +Creditcard+
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_instance_of Response, response
    assert_success response
    assert_equal '121212121212', response.authorization
    assert response.test?

    # Purchase with +ELV+ / +DirectDebit+
    @gateway.expects(:ssl_post).returns(successful_purchase_response)
    @options[:clearingtype] = 'elv'
    assert response = @gateway.purchase(@amount, @direct_debit, @options)
    assert_instance_of Response, response
    assert_success response
    assert response.test?
  end

  def test_successful_refund
    @gateway.expects(:ssl_post).returns(successful_purchase_response)
    @options[:sequencenumber] = 2

    assert response = @gateway.refund(@amount, "121212121212", @options)
    assert_instance_of Response, response
    assert_success response
    assert_equal '121212121212', response.authorization
    assert response.test?
  end

  def test_unsuccessful_request
    # Purchase with +Creditcard+
    @gateway.expects(:ssl_post).returns(failed_purchase_response)

    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert response.test?

    # Purchase with +ELV+ / +DirectDebit+
    @gateway.expects(:ssl_post).returns(failed_purchase_response)
    @options[:clearingtype] = 'elv'

    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert response.test?
  end

  private

  # Place raw successful response from gateway here
  def successful_purchase_response
    "status=APPROVED\ntxid=121212121212\nuserid=12121212"
  end

  # Place raw failed response from gateway here
  def failed_purchase_response
    "status=ERROR\nerrorcode=2003\nerrormessage=MerchantID not found or no rights"
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
