#!/usr/bin/env ruby

$LOAD_PATH.unshift File.expand_path(File.join(File.dirname(__FILE__), "lib"))

require 'rubygems' if RUBY_VERSION < "1.9"
require 'sinatra/base'
require 'haml'
require 'json'
require 'rufus/scheduler'
require 'pry'
require 'deep_merge'
require 'rest-client'
require 'models'
require 'hash-extensions'

class SensuDashboard < Sinatra::Base

  scheduler = Rufus::Scheduler.new
    
  scheduler.every '10m', :first_in => '1s' do
    @@checks = Hash.new
    Server.all.each do |server|
      url = "http://#{server.name}:4567/checks"
      begin
        checks = RestClient.get(url)
      rescue Exception => e
        checks = "{}"
        puts e
      end

      # Convert array to hash with check name as key
      chex = Hash.new 
      JSON.parse(checks).each do |c|
        c = c.symbolize_keys
        name = c[:name].to_sym
        chex[name] = c
      end
      @@checks[server[:name]] = chex
   end
    puts "Updated check data"
  end #scheduler
  
  before '/*' do
    @servers = Server.all
    @services = Service.all
    @views = View.all
  end


  get '/' do
    @viewdata = get_all
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
    services << Service.first(:id => params[:service])
    @servicedata = get_data(services)
    @priorityevents = extract_priorityevents(@servicedata)
    haml :services
  end

  get '/service/:service/events' do
    services = Array.new
    service = Service.first(:id => params[:service])
    services << service
    @servicedata = get_data(services)
    @events = @servicedata[service.name]
    haml :services
  end

  def extract_priorityevents(views)
    events = Hash.new
    views.each_pair do |view, data|
      events.deep_merge!(data[:events]) if data[:events]
    end
    events
  end

  def get_all
    services = Service.all
    get_data(services)
  end

  def get_view(view)
    services = View.first(:name => view).services
    get_data(services)
  end

  def get_data(services)
    output = Hash.new
    services.each do |service|
      d = build_hash(service.server.name)
      d = filter(d,service.filter) if service.filter
      d[:service_id] = service.id
      output[service.name] = d
    end
    output
  end
  
  def build_hash(server)
    data = Hash.new
    data[:events] = Hash.new
    data[:events][:critical] = Array.new
    data[:events][:high] = Array.new

    # Get all our events
    url = "http://#{server}:4567/events"
    begin
      events = RestClient.get(url)
    rescue Exception => e
      events = "{}"
      apifail(url,e)
    end
    data[:allevents] = JSON.parse(events)

    # Add custom data
    data[:allevents].each do |event|

      # Get event, client, check information
      event = event.symbolize_keys
      client = shortclient(event[:client])
      check = event[:check].to_sym
      checkdata = @@checks[server][check] unless check == :keepalive

      # Get priority from check
      if defined?(checkdata[:priority])
        event[:priority] = checkdata[:priority]
      else
          event[:priority] = "normal"
      end

      # Create array of critical/high priority events
      data[:events][:critical].push(event) if event[:priority] == "critical"
      data[:events][:high].push(event) if event[:priority] == "high"
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

  def filter(data,filter)
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
    client.gsub(/\..*/,'').to_sym
  end

  def apifail(url,error)
    puts "Failed to connect to #{url}"
    puts "Error: #{e}"
  end

end # Class SensuDashboard
