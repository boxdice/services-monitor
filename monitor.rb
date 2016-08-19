require "yaml"
require "net/http"
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
  request = Typhoeus::Request.new(settings["url"], followlocation: true)
  request.on_complete do |response|
    retry_count = JSON.parse(response.response_body)["retry_count"]
    if retry_count >= threshold
      slack_notify("Threshold of retry count of sidekiq jobs for #{cluster} (retry count: #{retry_count}) was reached")
    end
  end
  hydra.queue(request)
end
hydra.run

rabbitmq = @config["rabbitmq"]
uri = URI("#{rabbitmq["url"]}/api/queues")
req = Net::HTTP::Get.new(uri)
req.basic_auth rabbitmq["user"], rabbitmq["password"]
res = Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(req) }

messages = []
queues = JSON.parse(res.body)
queues.each do |queue|
  if (queue["messages_ready"] > 0 && queue["messages_ready_details"]["rate"] == 0.0)
    messages << "Messages in #{queue["name"]} queue are not being processed, consumers: #{queue["consumers"]}, messages: #{queue["messages_ready"]}, rate: #{queue["messages_ready_details"]["rate"]}"
  end
end

slack_notify(messages.join(",\n")) if messages.any?
