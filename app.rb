require "sinatra/base"
require "sinatra/reloader"
require "slim"
require "sass"
require "coffee-script"
require "active_support/all"

class Kaeritainess < Sinatra::Base
  configure :development do
    register Sinatra::Reloader
  end

  get "/" do
    slim :index
  end
end
