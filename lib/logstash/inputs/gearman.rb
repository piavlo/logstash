
require "logstash/inputs/base"
require "logstash/inputs/threadable"
require "logstash/namespace"

# Read events from a gearman server queue
#
# For more information about gearman, see <http://gearman.org//>
#
class LogStash::Inputs::Gearman < LogStash::Inputs::Threadable
  config_name "gearman"
  plugin_status "experimental"

  # The array of gearmand server to connect to.
  config :servers, :validate => :array, :default => ["127.0.0.1:4730"]

  # This sets the worker ID in a gearmand server so monitoring and reporting
  # commands can uniquely identify the various workers, and different
  # connections to job servers from the same worker.
  config :worker_id, :validate => :string

  # ruby-gearman worker uses a dedicated thread to healcheck the established connection to pool of gearman
  # servers. In case connection failes, it will remove it and try to reconnect every @reconnect_interval seconds.
  config :reconnect_interval, :validate => :number

  # Initial connection timeout in seconds for gearman worker to esablish connection with gearman server.
  config :connection_timeout, :validate => :number

  # The name of the gearman queue the worker should bind to.
  config :queue, :validate => :string, :required => true

  public
  def register
    require 'gearman'

    @format ||= "json_event"

    @opts = {}
    @opts[:network_timeout_sec] = @connection_timeout if @connection_timeout
    @opts[:reconnect_sec] = @reconnect_interval if @reconnect_interval
    @opts[:client_id] = @worker_id if @worker_id

    @worker = Gearman::Worker.new(@servers, @opts)
  end # def register

  public
  def run(output_queue)
    @worker.add_ability(@queue) do |data,job|
      socket = job.instance_variable_get(:@socket).peeraddr
      server = socket[2]
      port = socket[1]
      @logger.debug? and @logger.debug("Received job from queue " + @queue, :socket => socket, :job => job.inspect)
      #Forward input to LogStash
      output_queue << to_event(data, 'gearman://' + server + ':' + port.to_s() + '/' + @queue )
      true # Report success.
    end    
    @logger.debug? and @logger.debug("Starting gearman worker")
    while @worker.worker_enabled
      begin
        @worker.work
      rescue Gearman::ServerDownException => e
        @logger.warn("#{self.class.name}: Lost connection to gearmand server, sleeping...", :exception => e.inspect)
        sleep @reconnect_interval if @reconnect_interval
        #Need to reconnect to server here , does not seem to connect back automatically then server is back online.
        retry
      rescue Exception => e
        @logger.warn("#{self.class.name}: Caught Exception", :exception => e.inspect)
        retry
      end
    end
    @logger.debug? and @logger.debug("Stopping gearman worker")
  end # def run

  public
  def teardown
    #Stop executing new work
    @worker.worker_enabled = false
    #Finish work
    while @worker.status == :working
      sleep 1
    end
    #disconnect from all gearman servers
    @worker.update_job_servers([])
    finished
  end
end # class LogStash::Inputs::Gearman
