Spree::Shipment.class_eval do
  scope :fulfilling, -> { with_state('fulfilling') }
  scope :fulfill_failed, -> { with_state('fulfill_failed') }

  state_machines[:state] = nil # reset original state machine to start from scratch.

  # This is a modified version of the original spree shipment state machine
  # with the indicated changes.
  state_machine initial: :pending, use_transactions: false do
    event :ready do
      transition from: :pending, to: :shipped, if: :can_transition_from_pending_to_shipped?
      transition from: :pending, to: :ready, if: :can_transition_from_pending_to_ready?
    end

    event :pend do
      transition from: :ready, to: :pending
    end

    event :ship do
      transition from: [:ready, :canceled], to: :fulfilling # was to: :shipped
      # new transition
      transition from: :fulfilling, to: :shipped
    end
    after_transition to: :shipped, do: :after_ship

    # new callback
    before_transition to: :fulfilling, do: :before_fulfilling

    event :cancel do
      transition to: :canceled, from: [:pending, :ready]
      # new transition
      transition from: :fulfilling, to: :fulfill_failed
    end
    after_transition to: :canceled, do: :after_cancel

    event :resume do
      transition from: :canceled, to: :ready, if: :can_transition_from_canceled_to_ready?
      transition from: :canceled, to: :pending
    end
    after_transition from: :canceled, to: [:pending, :ready, :shipped], do: :after_resume

    after_transition do |shipment, transition|
      shipment.state_changes.create!(
        previous_state: transition.from,
        next_state:     transition.to,
        name:           'shipment'
      )
    end
  end

  # If there's an error submitting to the fulfillment service, we should halt
  # the transition to 'fulfill' and stay in 'ready'.  That way transient errors
  # will get rehandled.  If there are persistent errors, that should be treated
  # as a bug.
  def before_fulfilling
    response = Spree::Fulfillment.fulfill(self) # throws :halt on error, which aborts transition

    # Stop the transition to shipped if there was an error.
    unless response.success?
      if Spree::Fulfillment.config[:development_mode] &&
          response.params['faultstring'] =~ /the SellerSKU for Item Id: \S+ is invalid/
        Spree::Fulfillment.log 'Ignoring missing catalog item (test / dev setting - should not see this on prod)'
      else
        Spree::Fulfillment.log 'Abort - response was in error'
        throw :halt
      end
    end
  # TODO: Narrow down the catched exception
  rescue => ex
    Spree::Fulfillment.log "Shipment#before_fulfilling failed: #{ex.message}" \
      "\n#{ex.backtrace}"
    throw :halt
  end

  alias_method :orig_determine_state, :determine_state
  # Determines the appropriate +state+ according to the following logic:
  #
  # canceled   if order is canceled
  # pending    unless order is complete and +order.payment_state+ is +paid+
  # shipped    if already shipped (ie. does not change the state)
  # ready      all other cases
  def determine_state(order)
    return state if ['fulfilling', 'fulfill_failed', 'shipped'].include?(state)

    orig_determine_state(order)
  end
end
