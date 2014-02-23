require 'rack/test'
require 'spec_helper'

require './sensu-dashboard.rb'

describe SensuDashboard do
  include Rack::Test::Methods

  def app
    SensuDashboard
  end

  describe 'GET /' do
    context 'html' do
      it 'should return ok' do
        get '/'
        last_response.should be_ok
      end
    end
  end
end
