module Spree
  class Fulfillment
    CONFIG_FILE = Rails.root.join('config/fulfillment.yml')
    CONFIG = HashWithIndifferentAccess.new(YAML.load_file(CONFIG_FILE)[Rails.env])

    TrackingInfo = Struct.new(:carrier, :tracking_number, :ship_time) do
      def to_hash
        {
          carrier: carrier,
          tracking_number: tracking_number,
          ship_time: ship_time
        }
      end
    end

    def self.service_for(shipment)
      "#{adapter}_fulfillment".camelize.constantize.new(shipment)
    end

    def self.adapter
      return if defined?(@adapter)

      @adapter = config[:adapter]

      unless @adapter
        raise "Missing adapter for #{Rails.env} -- Check config/fulfillment.yml"
      end

      @adapter
    end

    def self.fulfill(shipment)
      service_for(shipment).fulfill
    end

    def self.config
      CONFIG
    end

    def self.log(msg)
      Rails.logger.info "**** spree_fulfillment: #{msg}"
    end

    # Passes any shipments that are ready to the fulfillment service
    def self.process_ready
      log 'Spree::Fulfillment.process_ready start'

      Spree::Shipment.ready.ids.each do |shipment_id|
        shipment = Spree::Shipment.find(shipment_id)

        next unless shipment && shipment.ready?

        log "Request to ship shipment ##{shipment.id}"
        begin
          shipment.ship!
        rescue => ex
          log "Spree::Fulfillment.process_ready: Failed to ship id #{shipment.id} due to #{ex}"
          Airbrake.notify(e) if defined?(Airbrake)
          # continue on and try other shipments so that one bad shipment doesn't
          # block an entire queue
        end
      end
    end

    # Gets tracking number and sends ship email when fulfillment house is done
    def self.process_fulfilling
      log 'Spree::Fulfillment.process_fulfilling start'

      Spree::Shipment.fulfilling.each do |shipment|
        next if shipment.shipped?

        tracking_info = remote_tracking_info(shipment)
        log "Spree::Fulfillment.process_fulfilling: tracking_info #{tracking_info}"
        next unless tracking_info

        if tracking_info == :error
          log 'Spree::Fulfillment.process_fulfilling: Could not retrieve' \
            "tracking information for shipment #{shipment.id} (order ID: "\
            "#{shipment.number})"
          shipment.cancel
        else
          log 'Spree::Fulfillment.process_fulfilling: Tracking information: ' \
            "#{tracking_info.inspect}"
          shipment.attributes = {
            shipped_at: tracking_info.ship_time,
            tracking: "#{tracking_info.carrier}::#{tracking_info.tracking_number}"
          }
          shipment.ship!
        end
      end
    end

    def self.remote_tracking_info(shipment)
      response = service_for(shipment).fetch_tracking_data
      return unless response
      log "Spree::Fulfillment.process_fulfilling: response #{response.inspect}"

      tracking_info = TrackingInfo.new(
        response.params.dig(:tracking_companies, shipment.number.to_s)&.first,
        response.params.dig(:tracking_numbers, shipment.number.to_s)&.first,
        response.params.dig(:shipping_date_times, shipment.number.to_s)&.first
      )

      unless tracking_info.carrier &&
        tracking_info.tracking_number &&
        tracking_info.ship_time
        return :error
      end

      tracking_info.to_hash
    end
  end
end
