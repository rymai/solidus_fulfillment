namespace :solidus_fulfillment do
  desc "Handles shipments that are ready for or have completed fulfillment"
  task process: :environment do
    Rake::Task['solidus_fulfillment:process:ready'].invoke
    Rake::Task['solidus_fulfillment:process:fulfilling'].invoke
  end

  namespace :process do
    desc "Passes any shipments that are ready to the fulfillment service"
    task ready: :environment do
      Spree::Fulfillment.process_ready
    end

    desc "Gets tracking number and sends ship email when fulfillment house is done"
    task fulfilling: :environment do
      Spree::Fulfillment.process_fulfilling
    end

    desc "Updates the stock levels"
    task stock_levels: :environment do
      Spree::Fulfillment.process_stock_levels
    end
  end
end
