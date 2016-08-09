require "yaml"
require "net/http"
require "uri"
require "json"

config = YAML.load_file("config/services.yml")

sidekiq = config["sidekiq"]
sidekiq.each_pair do |cluster, settings|
  uri = URI("#{settings["url"]}")
  response = Net::HTTP.get(uri)
  puts "#{cluster}: #{JSON.parse(response)["retry_count"]}"
end

rabbitmq = config["rabbitmq"]
uri = URI("#{rabbitmq["url"]}/api/queues")
req = Net::HTTP::Get.new(uri)
req.basic_auth rabbitmq["user"], rabbitmq["password"]
res = Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(req) }

rabbit_res = {}
queues = JSON.parse(res.body)
queues.each do |queue|
  results = {}
  name = queue["name"]

  results["consumers"] = queue["consumers"]
  results["messages_ready"] = queue["messages_ready"]
  results["rate"] = queue["messages_ready_details"]["rate"]
  puts "#{name}, consumers: #{results["consumers"]}, messages: #{results["messages_ready"]}, rate: #{results["rate"]}"

  rabbit_res[name] = results
end
