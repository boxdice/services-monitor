require "yaml"
require "net/http"
require "uri"
require "json"

config = YAML.load_file("config/services.yml")

sidekiq = config["sidekiq"]
sidekiq["clusters"].each_pair do |cluster, settings|
  uri = URI("#{settings["url"]}")
  response = Net::HTTP.get(uri)
  retry_count = JSON.parse(response)["retry_count"]
  threshold = sidekiq["threshold"]
  if retry_count >= threshold
    puts "Threshold of retry count of sidekiq jobs for #{cluster} (retry count: #{retry_count}) was reached"
  end
end

rabbitmq = config["rabbitmq"]
uri = URI("#{rabbitmq["url"]}/api/queues")
req = Net::HTTP::Get.new(uri)
req.basic_auth rabbitmq["user"], rabbitmq["password"]
res = Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(req) }

rabbit_res = {}
queues = JSON.parse(res.body)
queues.each do |queue|
  if (queue["messages_ready"] > 0 && queue["messages_ready_details"]["rate"] == 0.0)
    results = {}
    name = queue["name"]

    results["consumers"] = queue["consumers"]
    results["messages_ready"] = queue["messages_ready"]
    results["rate"] = queue["messages_ready_details"]["rate"]
    puts "Messages in #{name} queue are not being processed, consumers: #{results["consumers"]}, messages: #{results["messages_ready"]}, rate: #{results["rate"]}"
  end

  rabbit_res[name] = results
end
