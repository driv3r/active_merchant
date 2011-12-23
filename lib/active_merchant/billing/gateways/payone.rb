require 'digest/md5'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class PayoneGateway < Gateway

      URL = 'https://api.pay1.de/post-gateway/'

      CARDTYPE = {
        :visa => 'V', :master => 'M', :jsb => 'J', :american_express => 'A',
        :discover => 'C', :maestro => 'O', :diners_club => 'D'
      }

      # The card types supported by the payment gateway
      self.supported_cardtypes = [
        :visa, :master, :american_express, :discover, :jsb, :maestro, :diners_club
      ]

      # The countries the gateway supports merchants from as 2 digit ISO country codes
      # self.supported_countries = ['US']
      self.default_currency = 'EUR'
      self.money_format = :cents

      # The homepage URL of the gateway
      self.homepage_url = 'http://www.payone.de/'

      # The name of the gateway
      self.display_name = 'Payone'

      #  :login     => "mid"        # Merchant ID
      #  :password  => "portalid"   # Payment portal ID
      def initialize(options = {})
        requires!(options, :login, :password, :sub_account_id, :key)
        @options = options
        super
      end

      def authorize(money, creditcard, options = {})
        post = {}
        add_invoice(post, options)
        add_reference(post, options)
        add_payment_source(post, creditcard, options)
        add_address(post, creditcard, options)
        add_customer_data(post, options)
        add_amount(post, money, options)

        commit('preauthorization', money, post)
      end

      def purchase(money, creditcard, options = {})
        post = {}
        add_invoice(post, options)
        add_reference(post, options)
        add_payment_source(post, creditcard, options)
        add_address(post, creditcard, options)
        add_customer_data(post, options)
        add_amount(post, money, options)

        commit('authorization', money, post)
      end

      def capture(money, authorization, options = {})
        post = {}
        add_authorization(post, authorization)
        add_amount(post, money, options)
        commit('capture', money, post)
      end

      private

      def add_authorization(post, auth)
        post[:txid] = auth
      end

      def add_reference(post, options)
        post[:reference] = options[:reference]
      end

      def add_customer_data(post, options)
        if options.has_key? :email
          post[:email] = options[:email]
        end

        if options.has_key? :ip
          post[:ipaddress] = options[:ip]
        end
      end

      def add_address(post, creditcard, options)
        if address = options[:billing_address] || options[:address]
          post[:address1]    = address[:address1].to_s
          post[:address2]    = address[:address2].to_s unless address[:address2].blank?
          post[:company]    = address[:company].to_s
          post[:phone]      = address[:phone].to_s
          post[:zip]        = address[:zip].to_s
          post[:city]       = address[:city].to_s
          post[:country]    = address[:country].to_s # must be Country ISO code
          post[:state]      = address[:state].blank?  ? 'n/a' : address[:state]
        end
      end

      def add_invoice(post, options)
      end

      def add_amount(post, money, options)
        post[:amount]  = amount(money) if money
        post[:currency] = options[:currency] || currency(money)
      end

      #elv: Debit payment
      #cc: Credit card
      #rec: Invoice
      #vor: Advance payment
      #sb: Online Bank Transfer
      #cod: Cash on Delivery
      #wlt: e-wallet
      def add_payment_source(params, source, options={})
        case determine_funding_source(source)
        when :cc then add_creditcard(params, source, options)
        end
      end

      def add_creditcard(post, creditcard, options)
        post[:clearingtype] = 'cc'
        post[:cardpan]  = creditcard.number
        post[:cardtype] = CARDTYPE[creditcard.type.to_sym]
        post[:cardexpiredate ]  = expdate(creditcard)
        post[:cardcvc2] = creditcard.verification_value if creditcard.verification_value?
        post[:firstname] = creditcard.first_name
        post[:lastname]  = creditcard.last_name
      end

      def parse(body)
        response = {}

        body.split(/\n/).each do |pair|
          key,val = pair.split(/=/)
          response[key] = val
        end

        response
      end

      def commit(action, money, parameters)
        parameters[:request] = action

        response = parse( ssl_post(URL, post_data(action, parameters)) )

        Response.new(response["status"] == "APPROVED", message_from(response), response,
          :authorization => response["txid"],
          :test => test?,
          :cvv_result => response["cvvresponse"],
          :avs_result => { :code => response["avsresponse"] }
        )
      end

      def message_from(response)
        case response['status']
        when "APPROVED" then "This transaction has been approved"
        when "REDIRECT" then "Payment was redirected, awaiting for payment" # 3D-Secure/Online Bank Transfer/e-wallet
        when "ERROR"    then "This transaction has not been approved"
        end
      end

      def post_data(action, parameters = {})
        post = {}

        post[:portalid]  = @options[:password]
        post[:mid]       = @options[:login]
        post[:key]       = Digest::MD5.hexdigest(@options[:key])
        post[:aid]       = @options[:sub_account_id]
        post[:mode]      = test? ? 'test' : 'live'
        post[:encoding]  = 'UTF-8'

        request = post.merge(parameters).map {|key,value| "#{key}=#{CGI.escape(value.to_s)}"}.join("&")
        request
      end

      def determine_funding_source(source)
        case
        when CreditCard.card_companies.keys.include?(card_brand(source)) then :cc
        else raise ArgumentError, "Unsupported funding source provided"
        end
      end

      def expdate(creditcard)
        year  = sprintf("%.4i", creditcard.year)
        month = sprintf("%.2i", creditcard.month)

        "#{year[-2..-1]}#{month}"
      end
    end
  end
end
