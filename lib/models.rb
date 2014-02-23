require 'data_mapper'

DataMapper::Logger.new($stdout, :debug)
DataMapper.setup(:default, "sqlite3://#{Dir.pwd}/db/dashboard.db")

# Server model
class Server
  include DataMapper::Resource
  property :id, Serial
  property :name, String
  has n, :services
end

# Service model
class Service
  include DataMapper::Resource
  property :id, Serial
  property :name, String
  property :site, String
  property :type, String
  property :events, Boolean
  property :filter, String
  belongs_to :server
  has n, :views, through: Resource
end

# View model
class View
  include DataMapper::Resource
  property :id, Serial
  property :name, String
  has n, :services, through: Resource
end

DataMapper.auto_upgrade!
DataMapper.finalize
