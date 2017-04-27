require 'active_fulfillment'

ActiveFulfillment::Service.logger = Rails.logger
ActiveFulfillment::AmazonMarketplaceWebService.class_eval do
  # Monkeypatch of the original parse_tracking_response to include the shipping date.
  # Changed lines are marked.
  def parse_tracking_response(document)
    response = {
      tracking_numbers: {},
      tracking_companies: {},
      tracking_urls: {},
      shipping_date_times: {} # Additional key
    }

    tracking_numbers = document.css('FulfillmentShipmentPackage > member > TrackingNumber'.freeze)
    if tracking_numbers.present?
      order_id = document.at_css('FulfillmentOrder > SellerFulfillmentOrderId'.freeze).text.strip
      response[:tracking_numbers][order_id] = tracking_numbers.map{ |t| t.text.strip }
    end

    tracking_companies = document.css('FulfillmentShipmentPackage > member > CarrierCode'.freeze)
    if tracking_companies.present?
      order_id = document.at_css('FulfillmentOrder > SellerFulfillmentOrderId'.freeze).text.strip
      response[:tracking_companies][order_id] = tracking_companies.map{ |t| t.text.strip }
    end

    # Changes start here
    shipping_date_times = document.css('FulfillmentShipment > member > ShippingDateTime'.freeze)
    if shipping_date_times.present?
      response[:shipping_date_times][order_id] = shipping_date_times.map { |t| t.text.strip }
    end
    # Changes end here

    response[:response_status] = SUCCESS

    Response.new(success?(response), message_from(response), response)
  end
end

class AmazonFulfillment
  def initialize(shipment = nil)
    @shipment = shipment
  end

  # Runs inside a state_machine callback. So throwing :halt is how we abort things.
  def fulfill
    sleep 1 # avoid throttle from Amazon

    response = remote.fulfill(order_id, address, line_items, options)
    Spree::Fulfillment.log "Spree::AmazonFulfillment#fulfill: order_id: " \
      "#{order_id}\naddress: #{address}\nline_items: #{line_items}\noptions: " \
      "#{options}\nresponse: #{response.params}"

    response
  end

  # Returns the tracking number if there is one, else :error if there's a
  # problem with the shipment that will result in a permanent failure to
  # fulfill, else nil.
  def fetch_tracking_data
    sleep 1 # avoid throttle from Amazon

    response = begin
      remote.fetch_tracking_data([order_id])
    rescue => ex
      Spree::Fulfillment.log 'Spree::AmazonFulfillment#fetch_tracking_data: Failed to get ' \
        "tracking info for shipment #{@shipment.id} (order ID: #{order_id})"
      Spree::Fulfillment.log "Spree::AmazonFulfillment#fetch_tracking_data: #{ex}"
      Airbrake.notify(e) if defined?(Airbrake)

      return nil
    end

    Spree::Fulfillment.log "Spree::AmazonFulfillment#fetch_tracking_data: #{response.params}"

    response
  end

  # Returns the stock levels for the given skus
  def fetch_stock_levels(skus)
    sleep 1 # avoid throttle from Amazon

    response = begin
      remote.fetch_stock_levels(skus: skus)
    rescue => ex
      Spree::Fulfillment.log 'Spree::AmazonFulfillment#fetch_stock_levels: Failed to get ' \
        "stock levels"
      Spree::Fulfillment.log "Spree::AmazonFulfillment#fetch_stock_levels: #{ex}"
      Airbrake.notify(e) if defined?(Airbrake)

      return nil
    end

    Spree::Fulfillment.log "Spree::AmazonFulfillment#fetch_stock_levels: #{response.params}"

    response
  end

  private

  # For Amazon these are the API access key and secret.
  def credentials
    @credentials ||= {
      login: Spree::Fulfillment.config[:api_key],
      password: Spree::Fulfillment.config[:secret_key],
      seller_id: Spree::Fulfillment.config[:seller_id]
    }
  end

  def remote
    @remote ||= ActiveFulfillment::Base.service('amazon_marketplace_web').new(credentials)
  end

  def order_id
    @order_id ||= @shipment.number
  end

  def address
    @address ||= begin
      ship_address = @shipment.order.ship_address

      {
        name: "#{ship_address.firstname} #{ship_address.lastname}",
        address1: ship_address.address1,
        address2: ship_address.address2,
        city: ship_address.city,
        state: ship_address.state.abbr,
        country: ship_address.state.country.iso,
        zip: ship_address.zipcode
      }
    end
  end

  def max_quantity_failsafe(quantity)
    return quantity unless Spree::Fulfillment.config[:max_quantity_failsafe]

    [Spree::Fulfillment.config[:max_quantity_failsafe], quantity].min
  end

  def line_items
    @line_items ||= begin
      skus = @shipment.inventory_units.map do |inventory_unit|
        sku = inventory_unit.variant.sku
        raise "Missing sku for #{inventory_unit.variant}" if sku.blank?
        sku
      end.uniq

      skus.map do |sku|
        quantity = @shipment.inventory_units.select do |inventory_unit|
          inventory_unit.variant.sku == sku
        end.size

        {
          sku: sku,
          quantity: max_quantity_failsafe(quantity)
        }
      end
    end
  end

  def shipping_method
    return @shipping_method if defined?(@shipping_method)

    raw_shipping_method = @shipment.shipping_method
    @shipping_method = 'Standard' unless raw_shipping_method
    @shipping_method ||=
      case raw_shipping_method.name.downcase
      when /expedited/
        'Expedited'
      when /priority/
        'Priority'
      else
        'Standard'
      end
  end

  def options
    @options ||= {
      shipping_method: shipping_method,
      order_date: @shipment.order.created_at,
      comment: 'Thank you for your order.',
      email: @shipment.order.email
    }
  end
end
