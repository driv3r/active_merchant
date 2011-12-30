require 'digest/md5'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class PayoneGateway < Gateway
      API_VERSION    = '2.5'
      URL            = 'https://api.pay1.de/post-gateway/'
      ECOMMERCE_MODE = ['internet', '3dsecure', 'moto']
      CARDTYPE       = {
        :visa => 'V', :master => 'M', :jsb => 'J', :american_express => 'A',
        :discover => 'C', :maestro => 'O', :diners_club => 'D'
      }
      AVS_MESSAGES   = {
        "A" => "House number is ok, postal code is not",
        "F" => "House and postal code are ok",
        "N" => "Neither a house number or postal code are ok",
        "U" => "Request is not supported",
        "Z" => "Street number is not ok, but postal code is ok"
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

        commit('preauthorization', post)
      end

      def purchase(money, creditcard, options = {})
        post = {}
        add_invoice(post, options)
        add_reference(post, options)
        add_payment_source(post, creditcard, options)
        add_address(post, creditcard, options)
        add_customer_data(post, options)
        add_amount(post, money, options)

        commit('authorization', post)
      end

      def capture(money, authorization, options = {})
        post = {}
        add_authorization(post, authorization)
        add_amount(post, money, options)
        commit('capture', post)
      end

      def refund(money, authorization, options = {})
        post = {}

        add_amount(post, money, options)
        add_sequencenumber(post, options)
        add_authorization(post, authorization)

        commit('refund', post)
      end

      def credit(money, authorization, options = {})
        deprecated CREDIT_DEPRECATION_MESSAGE
        refund(money, authorization, options)
      end

      private

      def add_authorization(post, auth)
        post[:txid] = auth
      end

      def add_reference(post, options)
        post[:reference] = options[:order_id]
      end

      def add_sequencenumber(post, options)
        post[:sequencenumber] = options[:sequencenumber]
      end

      def add_customer_data(post, options)
        if options.has_key? :email
          post[:email] = options[:email]
        end

        if options.has_key? :ip
          post[:ip] = options[:ip]
        end
      end

      def add_address(post, creditcard, options)
        if address = options[:billing_address] || options[:address]
          post[:street]          = address[:address1].to_s
          post[:addressaddition] = address[:address2].to_s unless address[:address2].blank?
          post[:company]         = address[:company].to_s
          post[:telephonenumber] = address[:phone].to_s
          post[:zip]             = address[:zip].to_s
          post[:city]            = address[:city].to_s
          post[:country]         = address[:country].to_s # must be Country ISO code

          if ["US", "CA"].include?(address[:country]) and !address[:state].blank?
            post[:state]      = address[:state]
          end
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
        card_type = creditcard.brand || creditcard.type

        post[:clearingtype] = 'cc'
        post[:cardpan]  = creditcard.number
        post[:cardtype] = CARDTYPE[card_type.to_sym]
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

        unless response["protect_result_avs"].blank?
          avs_code = response["protect_result_avs"]
          response[:parsed_avs][:code] = avs_code
          response[:parsed_avs][:message] = AVS_MESSAGES[avs_code] if AVS_MESSAGES.has_key? avs_code
          response[:parsed_avs][:street_match] = ["A","F"].include? avs_code
          response[:parsed_avs][:postal_match] = ["Z","F"].include? avs_code
        end

        response
      end

      def commit(action, parameters)
        parameters[:request] = action

        response = parse( ssl_post(URL, post_data(action, parameters)) )

        Response.new(response["status"] == "APPROVED", message_from(response), response,
          :authorization => response["txid"],
          :test => test?,
          :cvv_result => response["cvvresponse"],
          :avs_result => response["parsed_avs"]
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
        post[:encoding]  = @options[:encoding] ? @options[:encoding] : 'UTF-8'

        if @options[:ecommercemode] and ECOMMERCE_MODE.include? @options[:ecommercemode]
          post[:ecommercemode] = @options[:ecommercemode]
        end

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
