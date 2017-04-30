SolidusFulfillment is a solidus extension to do fulfillment processing via
various fulfillment services when a shipment becomes ready.

The extension adds an additional state to the Shipment state machine called
`fulfilling` which acts as the transition between `ready` and `shipped`.

When a shipment becomes `ready` it is eligible for fulfillment:

1. A `solidus_fulfillment:process` rake task intended to be called from a cron
  job checks for `ready` shipments (by delegating to the
  `solidus_fulfillment:process:ready` task) and initiates the fulfillment via
  the merchant API.
1. If the fulfillment transaction succeeds, the shipment enters the `fulfilling`
  state.
1. The `solidus_fulfillment:process:fulfilling` rake task then queries the
  merchant's API for tracking numbers of any orders that are being fulfilled.
1. If the tracking numbers are found, the shipment transitions into the
  `shipped` state and an email is sent to the customer.

Stock levels can also be updated with the
`solidus_fulfillment:process:stock_levels` rake task which is intended to be
called from a cron job.

## Installation

### Add to your gemfile:

```ruby
gem 'whenever', require: false # if you want whenever to manage the cron job
gem 'solidus_fulfillment'
```

### Create config/fulfillment.yml:

```yml
development:
  adapter: amazon
  api_key: <YOUR AMAZON AWS API KEY>
  secret_key: <YOUR AMAZON AWS SECRET KEY>
  seller_id: <YOUR SELLER ID>
  development_mode: true

test:
  adapter: amazon
  api_key: <YOUR AMAZON AWS API KEY>
  secret_key: <YOUR AMAZON AWS SECRET KEY>
  seller_id: <YOUR SELLER ID>

production:
  adapter: amazon
  api_key: <YOUR AMAZON AWS API KEY>
  secret_key: <YOUR AMAZON AWS SECRET KEY>
  seller_id: <YOUR SELLER ID>
```

### Create config/schedule.rb:

```ruby
every :hour do
  rake "solidus_fulfillment:process"
end
```

### Add to deploy.rb:

```ruby
require 'whenever/capistrano' # if you want whenever to manage the cron job
```

### Configure the store

Set the SKU code for your products to be equal to the Amazon fulfillment SKU code.

----

Copyright (c) 2017 Rémy Coutable, released under the New BSD License
Copyright (c) 2011 WIMM Labs, released under the New BSD License
