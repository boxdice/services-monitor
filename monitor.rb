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
