require "yaml"
require "net/https"
require "uri"
require "json"
require "slack-notifier"
require "typhoeus"

@config = YAML.load_file("config/services.yml")

def slack_notify(message)
  slack = @config["slack"]
  hook = slack["hook"]
  user = slack["user"]
  channel = slack["channel"]

  slack_message = ""
  if slack["user_group"].to_s.empty?
    slack_message = "<!channel>: \n"
  else
    slack_message = "<!subteam^#{slack["user_group_id"]}|#{slack["user_group"]}>: \n"
  end
  slack_message += message

  notifier = Slack::Notifier.new hook, channel: channel, username: user
  notifier.ping slack_message
end

hydra = Typhoeus::Hydra.new
sidekiq = @config["sidekiq"]
threshold = sidekiq["threshold"]

sidekiq["clusters"].each_pair do |cluster, settings|
  url = settings["url"]
  request = Typhoeus::Request.new(url, followlocation: true)
  request.on_complete do |response|
    if response.success?
      retry_count = JSON.parse(response.response_body)["retry_count"]
      if retry_count >= threshold
        slack_notify("Threshold of retry count of sidekiq jobs for #{cluster} (retry count: #{retry_count}) was reached")
      end
    else
      slack_notify("Failed to get sidekiq stats for url: #{url}")
    end
  end
  hydra.queue(request)
end
hydra.run

rabbitmq = @config["rabbitmq"]

uri = URI.parse("#{rabbitmq["url"]}/api/queues?msg_rates_age=300&msg_rates_incr=60")
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true
http.verify_mode = OpenSSL::SSL::VERIFY_NONE

messages = []

begin
  request = Net::HTTP::Get.new(uri.request_uri)
  request.basic_auth rabbitmq["user"], rabbitmq["password"]
  res = http.request(request)

  queues = JSON.parse(res.body)
  queues.each do |queue|
    rate = if queue["message_stats"] && queue["message_stats"]["ack_details"]
      queue["message_stats"]["ack_details"]["avg_rate"]
    else
      queue["messages_ready_details"]["rate"]
    end
    if (queue["messages_ready"] > 0 && rate == 0.0)
      messages << "Messages in #{queue["name"]} queue are not being processed, consumers: #{queue["consumers"]}, messages: #{queue["messages_ready"]}, rate: #{queue["messages_ready_details"]["rate"]}"
    end
  end
rescue Exception => e
  messages << "Failed to get rabbitmq data, #{e.message}"
end

slack_notify(messages.join(",\n")) if messages.any?
