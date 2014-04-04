#!/usr/bin/env ruby

$LOAD_PATH.unshift File.expand_path(File.join(File.dirname(__FILE__), 'lib'))

require 'sinatra/base'
require 'haml'
require 'json'
require 'rufus/scheduler'
require 'pry'
require 'deep_merge'
require 'rest-client'
require 'models'
require 'hash-extensions'

# SensuDashboard
class SensuDashboard < Sinatra::Base
  scheduler = Rufus::Scheduler.new
  @@checks = {}
  @@clients = {}

  scheduler.every '10m', first_in: '1s' do
    Server.all.each do |server|
      @@checks[server[:name]] = {} unless @@checks[server[:name]].is_a?(Hash)
      url = "http://#{server.name}:4567/checks"
      begin
        checks = RestClient.get(url)
      rescue => e
        checks = '{}'
        puts "Problem getting checks for #{server} - #{e}"
      end

      # Convert array to hash with check name as key
      chex = {}
      JSON.parse(checks).each do |c|
        c = c.symbolize_keys
        name = c[:name].to_sym
        chex[name] = c
      end
      @@checks[server[:name]] = chex
    end
    puts 'Updated check data'

    Server.all.each do |server|
      @@clients[server[:name]] = {} unless @@clients[server[:name]].is_a?(Hash)
      url = "http://#{server.name}:4567/clients"
      begin
        checks = RestClient.get(url)
      rescue => e
        checks = '{}'
        puts "Problem getting clients for #{server} - #{e}"
      end

      # Convert array to hash with check name as key
      clientz = {}
      JSON.parse(checks).each do |c|
        c = c.symbolize_keys
        name = c[:name].to_sym
        clientz[name] = c
      end
      @@clients[server[:name]] = clientz
    end
  end # scheduler

  before '/*' do
    @servers = Server.all
    @services = Service.all
    @views = View.all
  end

  get '/' do
    @viewdata = all_services
    @priorityevents = extract_priorityevents(@viewdata)
    haml :views
  end

  get '/views/:view' do
    @viewdata = get_view(params[:view])
    @priorityevents = extract_priorityevents(@viewdata)
    haml :views
  end

  get '/service/:service' do
    services = Array.new
    services << Service.first(id: params[:service])
    @servicedata = get_data(services)
    if params[:events] == 'true'
      @events = @servicedata[services.first.name]
    else
      @priorityevents = extract_priorityevents(@servicedata)
    end
    haml :services
  end

  get '/server/:server' do
    @server = Server.first(id: params[:server])
    @serverdata = build_hash(@server.name)
    if params[:events] == 'true'
      @events = @serverdata
    else
      @priorityevents = @serverdata[:events]
    end
    haml :servers
  end

  get '/server/:server/checks' do
    @server = Server.first(id: params[:server])
    @serverdata = build_hash(@server.name)
    @checks = @@checks[@server.name]
    haml :checks
  end

  get '/server/:server/clients' do
    @server = Server.first(id: params[:server])
    @serverdata = build_hash(@server.name)
    @clients = @@clients[@server.name]
    haml :clients
  end

  get '/new' do
    haml :new
  end

  post '/server' do
    @server = Server.new(name: params[:server])
    if @server.save
      redirect "server/#{@server.id}"
    else
      haml :new
    end
  end

  post '/service' do
    @server = Server.first(name: params[:server])
    @service = Service.new(params[:service])
    @server.services << @service
    if @service.save
      redirect "service/#{@service.id}"
    else
      haml :new
    end
  end

  post '/view' do
    @view = View.new(params[:view])
    params[:services].each do |service|
      @service = Service.first(name: service)
      @view.services << @service
    end
    if @view.save
      redirect "views/#{@view.name}"
    else
      haml :new
    end
  end

  def extract_priorityevents(views)
    events = {}
    views.each_pair do |view, data|
      events.deep_merge!(data[:events]) if data[:events]
    end
    events
  end

  def all_services
    services = Service.all
    get_data(services)
  end

  def get_view(view)
    services = View.first(name: view).services
    get_data(services)
  end

  def get_data(services)
    output = {}
    services.each do |service|
      d = build_hash(service.server.name)
      d = filter(d, service.filter) if service.filter
      d[:service_id] = service.id
      output[service.name] = d
    end
    output
  end

  def build_hash(server)
    data = {}
    data[:events] = {}
    data[:events][:critical] = []
    data[:events][:high] = []

    # Get all our events
    url = "http://#{server}:4567/events"
    begin
      events = RestClient.get(url)
    rescue => e
      events = '{}'
      apifail(url, e)
    end
    data[:allevents] = JSON.parse(events)

    # Add custom data
    data[:allevents].each do |event|

      # Get event, client, check information
      event = event.symbolize_keys
      check = event[:check].to_sym
      checkdata = {}
      checkdata = @@checks[server][check] if check != :keepalive && defined?(@@checks[server]) && defined?(@@checks[server][check])

      # Get priority from check
      if defined?(checkdata[:priority])
        event[:priority] = checkdata[:priority]
      else
        event[:priority] = 'normal'
      end

      # Add length of time check has been failing
      interval = checkdata.has_key?(:interval) ? checkdata[:interval] : 60
      since = interval * event[:occurrences]
      mm = since / 60
      hh, mm = mm.divmod(60)
      dd, hh = hh.divmod(24)
      event[:since] = sprintf '%d days, %d hours, %d minutes', dd, hh, mm

      # Add description to event
      output = event[:output].split("\n")[0..-1].join(' ')
      event[:description] = checkdata.has_key?(:description) ? checkdata[:description] : output[0..80].gsub(/\s\w+\s*$/, ' ...')

      # Create array of critical/high priority events
      data[:events][:critical].push(event) if event[:priority] == 'critical'
      data[:events][:high].push(event) if event[:priority] == 'high'
    end

    # Filter/Count events by check output
    data[:warning] = data[:allevents].select { |hash| hash['status'] == 1 }
    data[:numwarning] = data[:warning].count
    data[:critical] = data[:allevents].select { |hash| hash['status'] == 2 }
    data[:numcritical] = data[:critical].count
    data[:unknown] = data[:allevents].select { |hash| hash['status'] == 3 }
    data[:numunknown] = data[:unknown].count
    data[:total] = data[:allevents].count
    data
  end

  def filter(data, filter)
    data[:events][:critical] = data[:events][:critical].select { |hash| hash['client'] =~ /#{filter}/ }
    data[:events][:high] = data[:events][:high].select { |hash| hash['client'] =~ /#{filter}/ }
    data[:critical] = data[:critical].select { |hash| hash['client'] =~ /#{filter}/ }
    data[:warning] = data[:warning].select { |hash| hash['client'] =~ /#{filter}/ }
    data[:unknown] = data[:unknown].select { |hash| hash['client'] =~ /#{filter}/ }
    data[:numcritical] = data[:critical].count
    data[:numwarning] = data[:warning].count
    data[:numunknown] = data[:unknown].count
    data[:total] = data[:numcritical] + data[:numwarning] + data[:numunknown]
    data
  end

  # Take FQDN and provide symbolized hostname
  def shortclient(client)
    client.gsub(/\..*/, '').to_sym
  end

  def apifail(url, error)
    puts "Failed to connect to #{url}"
    puts "Error: #{error}"
  end
end # Class SensuDashboard
