require "logstash/outputs/base"
require "logstash/namespace"

# Send events to a gearman server queue
#
# For more information about gearman, see <http://gearman.org//>
#
class LogStash::Outputs::Gearman < LogStash::Outputs::Base
  config_name "gearman"
  plugin_status "stable"

  # The array of gearmand server to connect to.
  config :servers, :validate => :array, :default => ["127.0.0.1:4730"]

  # The name of the gearman queue the worker should bind to.
  config :queue, :validate => :string, :required => true

  public
  def register
    require 'gearman'

  	@client = Gearman::Client.new(@servers)
    @taskset = Gearman::TaskSet.new(@client)
  end # def register

  public
  def receive(event)
  	return unless output?(event)

    @logger.debug? and @logger.debug("sending event as gearman job", :event => event)

  	task = Gearman::Task.new(@queue, event.to_json, { :background => true })
    @taskset.add_task(task)
    @taskset.wait(0)
  end # def event
end # class LogStash::Outputs::Gearman
