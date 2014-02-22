require 'rubygems' if RUBY_VERSION < "1.9"
require 'data_mapper'

DataMapper::Logger.new($stdout, :debug)
DataMapper.setup(:default, "sqlite3://#{Dir.pwd}/db/dashboard.db")

class Server
  include DataMapper::Resource
  property :id, Serial
  property :name, String
  has n, :services
end

class Service
  include DataMapper::Resource
  property :id, Serial
  property :name, String
  property :site, String
  property :type, String
  property :events, Boolean
  property :filter, String
  belongs_to :server
  has n, :views, :through => Resource
end

class View
  include DataMapper::Resource
  property :id, Serial
  property :name, String
  has n, :services, :through => Resource
end

DataMapper.auto_upgrade!
DataMapper.finalize
