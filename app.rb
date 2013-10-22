# coding: utf-8

require "sinatra/base"
require "sinatra/reloader"
require "slim"
require "sass"
require "coffee-script"
require "active_support/all"
require "randexp"
require "omniauth-twitter"
require "mongoid"
require "twitter"
require "logger"
require "yaml"

Mongoid.load! "./config/mongoid.yml"

class Kaeritai
  include Mongoid::Document
  include Mongoid::Timestamps::Created

  field :serial, type: Integer
  field :user_id, type: Integer
  field :tweet_id, type: Integer
  field :text, type: String

  scope :by_day, ->(datetime){where :created_at.gte => datetime.beginning_of_day.to_s, :created_at.lte => datetime.end_of_day.to_s}

  default_scope desc(:created_at)

  def tweet
    case rand(15)
    when 0
      client.update_with_media "#{self.text} (#{self.serial.with_delimiter}回目)", File.new(Dir.glob("./media/*").sample)
    else
      client.update "#{self.text} (#{self.serial.with_delimiter}回目)"
    end
  end

  def initialize attrs = nil
    super
    self.serial = self.class.count + 1
    self.user_id = attrs[:user_id]
    self.text = kaeritai_text
  end

  private
  def client
    Twitter::Client.new(
      consumer_key: ENV["CLIENT_CONSUMER_KEY"],
      consumer_secret: ENV["CLIENT_CONSUMER_SECRET"],
      oauth_token: ENV["CLIENT_ACCESS_TOKEN"],
      oauth_token_secret: ENV["CLIENT_ACCESS_TOKEN_SECRET"],
    )
  end

  def kaeritai_text
    seeds = YAML.load_file "./config/seeds.yml"
    seeds.values.inject "" {|text, seed| text + generate_text(seed)}
  end

  def generate_text seed
    sum = seed.inject 0 do |sum, item|
      item[:range] = sum...(sum + item[:weight])
      sum + item[:weight]
    end

    dice = rand sum

    seed.each do |item|
      next unless item[:range].include? dice

      if item[:pattern].empty?
        return ""
      else
        return Regexp.compile(item[:pattern]).generate
      end
    end
  end
end

class Fixnum
  def with_delimiter
    self.to_s.reverse.gsub(/(\d{3})(?=\d)/, "\1,").reverse
  end
end

class Kaeritainess < Sinatra::Base
  log = Logger.new STDOUT
  STDOUT.sync = true

  configure :development do
    register Sinatra::Reloader
  end

  configure do
    enable :sessions, :logging

    use OmniAuth::Builder do
      provider :twitter, ENV["TWITTER_CONSUMER_KEY"], ENV["TWITTER_CONSUMER_SECRET"]
    end
  end

  helpers do
    def current_user_id
      session[:current_user_id]
    end

    def current_user_nickname
      session[:current_user_nickname]
    end

    def authenticated?
      current_user_id.present?
    end
  end

  get "/" do
    slim :index
  end

  get "/signin" do
    redirect to "/auth/twitter"
  end

  get "/signout" do
    session[:current_user_id] = session[:current_user_nickname] = nil
    redirect to "/"
  end

  post "/create" do
    redirect to "/" unless authenticated?
    @kaeritai = Kaeritai.new user_id: current_user_id
    tweet = @kaeritai.tweet

    if tweet
      @kaeritai.tweet_id = tweet.id
      @kaeritai.save
      log.info "@#{current_user_nickname} just created a kaeritai ##{@kaeritai.serial}."
      redirect to "/kaeritai/" + @kaeritai.serial.to_s
    else
      redirect to "/failure"
    end
  end

  get "/kaeritai/:serial" do
    begin
      @kaeritai = Kaeritai.find_by serial: params[:serial]
      slim :show
    rescue
      redirect to "/failure"
    end
  end

  get "/auth/twitter/callback" do
    auth = env["omniauth.auth"]
    session[:current_user_id] = auth["uid"]
    session[:current_user_nickname] = auth["info"]["nickname"]
    redirect to "/"
  end

  get "/auth/failure" do
    redirect to "/failure"
  end

  get "/failure" do
    slim :failure
  end
end
