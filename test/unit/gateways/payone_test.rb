require 'test_helper'

class PayoneTest < Test::Unit::TestCase
  def setup
    @gateway = PayoneGateway.new(
                 :login => '66699',
                 :password => '666999',
                 :key => 'some secret text',
                 :sub_account_id => '555',
                 :reference => "someref"
               )

    @credit_card = credit_card
    @amount = 100

    @options = {
      :order_id => '1',
      :billing_address => address,
      :description => 'Store Purchase'
    }
  end

  def test_successful_purchase
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_instance_of Response, response
    assert_success response

    # Replace with authorization number from the successful response
    assert_equal '121212121212', response.authorization
    assert response.test?
  end

  def test_unsuccessful_request
    @gateway.expects(:ssl_post).returns(failed_purchase_response)

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
